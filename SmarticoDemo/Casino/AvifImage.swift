import ImageIO
import QuartzCore
import SwiftUI
import UIKit

/**
 * Remote AVIF image, still or animated ("avis") — the iOS side of
 * AvifDecoder.kt.
 *
 * On Android, Coil hands GIF, animated WebP and animated HEIF to the platform
 * ImageDecoder but does not recognise AVIF sequences, so the Kotlin demo claims
 * them by their ftyp brand. iOS 16+ ImageIO reads both flavours natively: a
 * plain AVIF is one image, an image sequence is a `public.avis` source whose
 * frames carry their own delay under `{AVIS}`. No decoder dependency.
 *
 * What it does NOT use: `CGAnimateImageDataWithBlock`. It plays these files,
 * but decodes on the main queue at whatever pace it manages (≈60 ms a frame
 * for the 960×540 slot clips), so a 3 s clip takes 4.5 s. Decoding the frames
 * ourselves off the main thread runs at the clip's own 24 fps, and when a
 * frame is late we skip to the one that is due instead of slowing down.
 *
 * - `maxPixelSize`: downsample stills (lobby thumbnails) at decode time.
 * - `animate: false`: show the first frame of a sequence only.
 * - `replayKey`: change it to play the same sequence again from frame 0 (the
 *   game's "one spin = one play" — Kotlin rebuilds the node with `key(spinSeq)`).
 *
 * A sequence plays as many times as its own loop count says (the slot clips say
 * once) and then holds its last frame. Until the first frame of a new url is
 * ready the previous picture stays up, so swapping clips never flashes empty.
 */
struct AvifImage: View {
    let url: String?
    var contentMode: ContentMode = .fill
    var maxPixelSize: CGFloat? = nil
    var animate: Bool = true
    var replayKey: Int = 0

    var body: some View {
        AvifRepresentable(
            url: url.flatMap { $0.isEmpty ? nil : URL(string: $0) },
            contentMode: contentMode,
            maxPixelSize: maxPixelSize,
            animate: animate,
            replayKey: replayKey
        )
    }
}

private struct AvifRepresentable: UIViewRepresentable {
    let url: URL?
    let contentMode: ContentMode
    let maxPixelSize: CGFloat?
    let animate: Bool
    let replayKey: Int

    func makeUIView(context: Context) -> AvifPlayerView {
        let view = AvifPlayerView()
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .vertical)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        update(view)
        return view
    }

    func updateUIView(_ view: AvifPlayerView, context: Context) {
        update(view)
    }

    private func update(_ view: AvifPlayerView) {
        view.layer.contentsGravity = contentMode == .fill ? .resizeAspectFill : .resizeAspect
        view.load(AvifRequest(url: url, maxPixelSize: maxPixelSize, animate: animate, replayKey: replayKey))
    }

    static func dismantleUIView(_ view: AvifPlayerView, coordinator: ()) {
        view.stop()
    }
}

private struct AvifRequest: Equatable {
    let url: URL?
    let maxPixelSize: CGFloat?
    let animate: Bool
    let replayKey: Int
}

/** Flag shared between the main thread and the decode queue. */
private final class Playback: @unchecked Sendable {
    private let lock = NSLock()
    private var _cancelled = false

    var cancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return _cancelled
    }

    func cancel() {
        lock.lock(); _cancelled = true; lock.unlock()
    }
}

/** A frame handed from the decode queue to the main thread. */
private struct Frame: @unchecked Sendable {
    let image: CGImage
}

/** Draws decoded frames straight into its layer's contents. */
final class AvifPlayerView: UIView {
    private var current: AvifRequest?
    private var playback: Playback?

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        isOpaque = false
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    fileprivate func load(_ request: AvifRequest) {
        if request == current { return }
        let sameUrl = request.url == current?.url
        current = request
        stop()
        guard let url = request.url else {
            layer.contents = nil
            return
        }
        // a cached still shows at once; otherwise the old picture stays up until
        // the first new frame lands (a replay of the same clip keeps its last frame)
        if !sameUrl, let still = AvifCache.shared.still(url, request.maxPixelSize) {
            layer.contents = still
        }
        let playback = Playback()
        self.playback = playback
        Task { [weak self] in
            let data: Data
            do {
                data = try await AvifCache.shared.data(url)
            } catch {
                demoLog("avif load failed \(url.lastPathComponent): \(error.localizedDescription)")
                return
            }
            if playback.cancelled { return }
            AvifDecoder.queue.async {
                AvifDecoder.render(data, url: url, request: request, playback: playback) { frame in
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated {
                            guard let self = self, !playback.cancelled else { return }
                            self.layer.contents = frame.image
                        }
                    }
                }
            }
        }
    }

    func stop() {
        playback?.cancel()
        playback = nil
    }

    // a looping sequence would otherwise keep decoding for a view that is gone
    deinit { playback?.cancel() }
}

/** Decoding: stills once (cached), sequences frame by frame on a timer. */
private enum AvifDecoder {
    /** One concurrent queue; each playback chains its own frames with asyncAfter. */
    static let queue = DispatchQueue(label: "ai.smartico.demo.avif", qos: .userInitiated, attributes: .concurrent)

    private static let decodeOptions = [kCGImageSourceShouldCacheImmediately: true] as CFDictionary

    static func render(
        _ data: Data,
        url: URL,
        request: AvifRequest,
        playback: Playback,
        show: @escaping (Frame) -> Void
    ) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            demoLog("avif: ImageIO cannot read \(url.lastPathComponent)")
            return
        }
        let count = CGImageSourceGetCount(source)
        if count <= 1 || !request.animate {
            if let still = AvifCache.shared.still(url, request.maxPixelSize) ?? decodeStill(source, request.maxPixelSize) {
                AvifCache.shared.storeStill(still, url, request.maxPixelSize)
                show(Frame(image: still))
            } else {
                demoLog("avif: no frame in \(url.lastPathComponent)")
            }
            return
        }
        let loops = loopCount(source)
        let clip = Clip(name: url.lastPathComponent, count: count, loops: loops, start: CACurrentMediaTime())
        play(source, clip, index: 0, pass: 1, shown: 0, due: clip.start, playback: playback, show: show)
    }

    private struct Clip {
        let name: String
        let count: Int
        let loops: Int // 0 = forever
        let start: CFTimeInterval
    }

    /**
     * Shows frame `index` (decoded now) and schedules the next one at its due
     * time. When decoding falls behind, jump to the frame that is due instead
     * of stretching the clip.
     */
    private static func play(
        _ source: CGImageSource,
        _ clip: Clip,
        index: Int,
        pass: Int,
        shown: Int,
        due: CFTimeInterval,
        playback: Playback,
        show: @escaping (Frame) -> Void
    ) {
        if playback.cancelled { return }
        var shown = shown
        if let image = CGImageSourceCreateImageAtIndex(source, index, decodeOptions) {
            show(Frame(image: image))
            shown += 1
        }
        let count = clip.count
        var next = index + 1
        var nextDue = due + delay(source, index)
        let now = CACurrentMediaTime()
        while nextDue < now && next < count - 1 { // late: skip, but never past the final frame
            nextDue += delay(source, next)
            next += 1
        }
        var nextPass = pass
        if next >= count {
            if clip.loops != 0 && pass >= clip.loops { // played out: hold the last frame
                demoLog(String(format: "avif %@: played %d of %d frames in %.2fs", clip.name, shown, count * pass, CACurrentMediaTime() - clip.start))
                return
            }
            next = 0
            nextPass += 1
        }
        queue.asyncAfter(deadline: .now() + max(0, nextDue - CACurrentMediaTime())) {
            play(source, clip, index: next, pass: nextPass, shown: shown, due: nextDue, playback: playback, show: show)
        }
    }

    private static func decodeStill(_ source: CGImageSource, _ maxPixelSize: CGFloat?) -> CGImage? {
        guard let maxPixelSize = maxPixelSize else {
            return CGImageSourceCreateImageAtIndex(source, 0, decodeOptions)
        }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options)
    }

    /** The sequence dictionary of the file's container — `{AVIS}` here, any animated type otherwise. */
    private static let sequenceKeys: [CFString] = [
        "{AVIS}" as CFString, kCGImagePropertyHEICSDictionary, kCGImagePropertyGIFDictionary,
        kCGImagePropertyPNGDictionary, kCGImagePropertyWebPDictionary,
    ]

    private static func sequenceDict(_ props: CFDictionary?) -> [String: Any]? {
        guard let props = props as? [String: Any] else { return nil }
        for key in sequenceKeys {
            if let d = props[key as String] as? [String: Any] { return d }
        }
        return nil
    }

    private static func loopCount(_ source: CGImageSource) -> Int {
        let d = sequenceDict(CGImageSourceCopyProperties(source, nil))
        return (d?["LoopCount"] as? NSNumber)?.intValue ?? 0
    }

    /**
     * A frame's delay. ImageIO clamps short delays to 0.1 s in `DelayTime`
     * (browser rule for GIFs); the clip's real 24 fps lives in `UnclampedDelayTime`.
     */
    private static func delay(_ source: CGImageSource, _ index: Int) -> CFTimeInterval {
        let d = sequenceDict(CGImageSourceCopyPropertiesAtIndex(source, index, nil))
        let v = (d?["UnclampedDelayTime"] as? NSNumber)?.doubleValue ?? (d?["DelayTime"] as? NSNumber)?.doubleValue ?? 0
        return v > 0.01 ? v : 1.0 / 24.0
    }
}

/**
 * Bytes and decoded stills, shared by every AvifImage. The game opens with four
 * ~1 MB clips, so bytes are kept in memory (bounded) and requests for the same
 * url are coalesced; stills are kept decoded so lobby tiles do not re-decode
 * on every scroll.
 */
final class AvifCache: @unchecked Sendable {
    static let shared = AvifCache()

    private let bytes = NSCache<NSURL, NSData>()
    private let stills = NSCache<NSString, CGImage>()
    private let lock = NSLock()
    private var inFlight: [URL: Task<Data, Error>] = [:]

    /** Disk cache of its own: the default URLCache is too small for the clips. */
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 0, diskCapacity: 200 * 1024 * 1024, directory: nil)
        config.requestCachePolicy = .returnCacheDataElseLoad
        return URLSession(configuration: config)
    }()

    private init() {
        bytes.totalCostLimit = 48 * 1024 * 1024
        stills.totalCostLimit = 32 * 1024 * 1024
    }

    func data(_ url: URL) async throws -> Data {
        if let d = bytes.object(forKey: url as NSURL) { return d as Data }
        let task: Task<Data, Error> = lock.withLock {
            if let t = inFlight[url] { return t }
            let session = self.session
            let t = Task<Data, Error> {
                let (data, response) = try await session.data(from: url)
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    throw URLError(.badServerResponse)
                }
                return data
            }
            inFlight[url] = t
            return t
        }
        defer { _ = lock.withLock { inFlight.removeValue(forKey: url) } }
        let data = try await task.value
        bytes.setObject(data as NSData, forKey: url as NSURL, cost: data.count)
        return data
    }

    /** Warm the cache so the first play starts at once (GameScreen.kt enqueues the clips the same way). */
    func prefetch(_ urls: [String]) {
        for s in urls {
            guard let url = URL(string: s) else { continue }
            Task { _ = try? await data(url) }
        }
    }

    fileprivate func still(_ url: URL, _ maxPixelSize: CGFloat?) -> CGImage? {
        stills.object(forKey: key(url, maxPixelSize))
    }

    fileprivate func storeStill(_ image: CGImage, _ url: URL, _ maxPixelSize: CGFloat?) {
        stills.setObject(image, forKey: key(url, maxPixelSize), cost: image.bytesPerRow * image.height)
    }

    private func key(_ url: URL, _ maxPixelSize: CGFloat?) -> NSString {
        "\(url.absoluteString)@\(Int(maxPixelSize ?? 0))" as NSString
    }
}
