import SwiftUI

// Palette lifted from the web fake-casino so the demo looks familiar
// (MainActivity.kt / Chrome.kt). Spelled as `Color` statics so call sites read
// `.foregroundColor(.muted)`.
extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }

    static let bg = Color(hex: 0x0F1020)
    static let card = Color(hex: 0x1A1B30)
    static let accent = Color(hex: 0x7C5CFF)
    static let muted = Color(hex: 0x8A8BA6)
    static let good = Color(hex: 0x7CD39A)
    static let gold = Color(hex: 0xFFD479)
    /** Filled progress once the mission is complete. */
    static let progressDone = Color(hex: 0x1F6D47)
    /** Header / bottom bar background (Chrome.kt). */
    static let chromeBg = Color(hex: 0x15162A)
    static let chromeBorder = Color(hex: 0x2A2B45)
    static let danger = Color(hex: 0xFF6B6B)
}

// ---------------------------------------------------------------------------
// Shared view helpers — Ui.kt. Every screen is built from these, so the D2
// screens stay down to "here's my list, here's a row".
// ---------------------------------------------------------------------------

/**
 * Server text fields carry HTML markup — strip it before display. A `<style>`
 * or `<script>` block goes whole, body included: operator-styled descriptions
 * (a tournament's "More Info") start with a stylesheet, and stripping only the
 * tags would put that CSS on screen as text. What the markup's indentation
 * leaves behind is tidied too (line-edge spaces, runs of blank lines); single
 * line texts are unaffected.
 */
func stripHtml(_ s: String?) -> String {
    (s ?? "")
        .replacingOccurrences(of: "<(style|script)\\b[^>]*>[\\s\\S]*?</\\1\\s*>", with: "", options: [.regularExpression, .caseInsensitive])
        .replacingOccurrences(of: "<[^>]*>", with: "", options: .regularExpression)
        .replacingOccurrences(of: "&nbsp;", with: " ")
        .replacingOccurrences(of: "[ \\t]*\\n[ \\t]*", with: "\n", options: .regularExpression)
        .replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

/**
 * Loads data once per screen and renders loading/error/empty states around it.
 * Keeps every screen down to "here's my list, here's a row".
 * `reloadKey` re-runs the load when it changes.
 */
struct ApiList<T, Row: View>: View {
    let title: String
    let load: () async throws -> [T]
    var reloadKey: AnyHashable = 0
    @ViewBuilder let row: (T) -> Row

    @State private var state: Result<[T], Error>?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.white)
                .padding(.vertical, 12)
            switch state {
            case nil:
                Loading()
            case .failure(let error)?:
                Text("Error: \(error.localizedDescription)").foregroundColor(.danger)
                Spacer()
            case .success(let items)? where items.isEmpty:
                Text("Nothing here yet.").foregroundColor(.muted)
                Spacer()
            case .success(let items)?:
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(items.indices, id: \.self) { i in row(items[i]) }
                    }
                    .padding(.bottom, 24)
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: reloadKey) {
            do {
                state = .success(try await load())
            } catch {
                state = .failure(error)
            }
        }
    }
}

struct Loading: View {
    var body: some View {
        ProgressView()
            .progressViewStyle(.circular)
            .tint(.accent)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/** Rounded card surface (Ui.kt `Card`). */
struct Card<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.card)
            .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

struct Title: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).font(.system(size: 15, weight: .bold)).foregroundColor(.white)
    }
}

struct Meta: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).font(.system(size: 12)).foregroundColor(.muted)
    }
}

/** Remote image thumbnail; nothing at all when there is no url. */
struct Thumb: View {
    let url: String?
    var size: CGFloat = 56

    var body: some View {
        if let url = url, !url.isEmpty, let u = URL(string: url) {
            AsyncImage(url: u) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                Color.clear
            }
            .frame(width: size, height: size)
        }
    }
}

/**
 * Mission/level progress. The fill ANIMATES to its new value (650ms, ease-out)
 * so a push-driven jump reads as movement rather than a redraw, and turns green
 * once the item is complete — same behaviour as the RN demo's ProgressBar.
 * (Ui.kt `Progress`; renamed because Foundation already has a `Progress`.)
 */
struct ProgressBar: View {
    let percent: Double
    var completed: Bool = false

    var body: some View {
        let target = min(max(percent / 100.0, 0), 1)
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.chromeBorder)
                Capsule()
                    .fill(completed ? Color.progressDone : Color.accent)
                    .frame(width: geo.size.width * target)
                    .animation(.easeOut(duration: 0.65), value: target)
            }
        }
        .frame(height: 6)
    }
}

/** Small status pill (Locked / Completed / In Progress …). */
struct Badge: View {
    let label: String
    let tone: Color

    var body: some View {
        Text(label)
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(tone)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tone.opacity(0.18))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

/** Upper-case section caption (Ui.kt `Section`; SwiftUI already has a `Section`). */
struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(.muted)
            .padding(.bottom, 4)
    }
}

/** "2d 03:04:05" style remaining time, or nil once the deadline has passed. */
func countdown(_ endTs: Int64, now: Int64) -> String? {
    let left = endTs - now
    if left <= 0 { return nil }
    let s = left / 1000
    let d = s / 86400
    let h = (s % 86400) / 3600
    let m = (s % 3600) / 60
    return (d > 0 ? "\(d)d " : "") + String(format: "%02d:%02d:%02d", h, m, s % 60)
}

/** Compact remaining time for tiles: "2d 3h" once past a day, else h:mm:ss. */
func countdownShort(_ endTs: Int64, now: Int64) -> String {
    let left = endTs - now
    if left <= 0 { return "—" }
    let s = left / 1000
    let d = s / 86400
    let h = (s % 86400) / 3600
    return d > 0 ? "\(d)d \(h)h" : String(format: "%02d:%02d:%02d", h, (s % 3600) / 60, s % 60)
}

/** "August 12 — August 19", the range shown above a tournament's details. */
func dateRange(_ startTs: Int64?, _ endTs: Int64?) -> String {
    let fmt = DateFormatter()
    fmt.locale = Locale(identifier: "en_US_POSIX")
    fmt.dateFormat = "MMMM dd"
    func f(_ ts: Int64?) -> String {
        guard let ts = ts, ts > 0 else { return "—" }
        return fmt.string(from: Date(timeIntervalSince1970: Double(ts) / 1000))
    }
    return "\(f(startTs)) — \(f(endTs))"
}

/** Wall-clock milliseconds, the unit every server timestamp uses. */
func nowMillis() -> Int64 {
    Int64(Date().timeIntervalSince1970 * 1000)
}

/**
 * A ticking clock (Ui.kt `rememberNow`), live only while `active` — a screen
 * with no timer stays idle. Use as `@StateObject private var clock = NowTicker()`
 * and read `clock.now`.
 */
@MainActor
final class NowTicker: ObservableObject {
    @Published private(set) var now: Int64 = nowMillis()
    private var timer: Timer?

    init(active: Bool = true) {
        setActive(active)
    }

    func setActive(_ active: Bool) {
        timer?.invalidate()
        timer = nil
        guard active else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.now = nowMillis() }
        }
    }

    deinit { timer?.invalidate() }
}

/** A button that runs an async action and shows its result inline. */
struct ActionButton: View {
    let label: String
    var onResult: (String) -> Void = { _ in }
    let action: () async throws -> String

    @State private var busy = false

    var body: some View {
        Button {
            busy = true
            Task {
                let msg: String
                do { msg = try await action() } catch { msg = "Failed: \(error.localizedDescription)" }
                busy = false
                onResult(msg)
            }
        } label: {
            Text(busy ? "…" : label)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(busy ? Color.muted : Color.accent)
                .clipShape(Capsule())
        }
        .disabled(busy)
    }
}
