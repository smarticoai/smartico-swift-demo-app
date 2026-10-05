import SmarticoPublicAPI
import SwiftUI
import WebKit

/**
 * Campaign popups (cid 110, activityType 30).
 *
 * The SDK owns the pipeline — dedupe, queue, and the bcid handshake. This host
 * only decides WHEN to show one (here: as soon as nothing else is showing) and
 * renders the transparent WebView the operator's HTML lands in.
 */
struct PopupHost: View {
    @ObservedObject private var sdk = Sdk.shared
    @State private var current: EngagementPayload?
    /** One WebView per popup: a fresh key whenever a popup is taken off the queue. */
    @State private var currentKey = UUID()
    @State private var visible = false

    var body: some View {
        ZStack {
            // The WebView is ALWAYS in the hierarchy while a popup is current,
            // never created on `visible`: the wrapper page only reports "ready
            // to be shown" after it has loaded and rendered, so a WebView that
            // is created on `visible` can never get there — the popup is taken
            // off the queue and then silently never appears. Instead it starts
            // INVISIBLE (loads, runs JS, takes no touches) and is revealed when
            // the page says it is ready.
            if let payload = current {
                PopupWebView(
                    payload: payload,
                    onReadyToShow: { visible = true },
                    onClose: {
                        visible = false
                        current = nil
                    }
                )
                .id(currentKey)
                .opacity(visible ? 1 : 0)
                .allowsHitTesting(visible)
                .animation(.easeInOut(duration: 0.25), value: visible)
                .ignoresSafeArea()
            }
        }
        // pump: take the next popup whenever the queue has one and we're free
        .onAppear(perform: pump)
        .onChange(of: sdk.pendingPopups) { _ in pump() }
        .onChange(of: current == nil) { _ in pump() }
    }

    private func pump() {
        if current == nil && Smartico.pendingEngagements() > 0 {
            current = Smartico.takeEngagement()
            currentKey = UUID()
            visible = false
            demoLog("popup taken, opening wrapper (uid=\(current.map { engagementUid($0) } ?? ""))")
        }
    }
}

/**
 * The transparent WKWebView a popup renders in. The wrapper page posts its
 * bridge messages to `window.webkit.messageHandlers.SmarticoBridge` (the
 * tracker's NativeBridge.ts looks for that handler first, so no JS shim is
 * needed) and receives the engagement through `evaluateJavaScript`.
 */
private struct PopupWebView: UIViewRepresentable {
    let payload: EngagementPayload
    let onReadyToShow: () -> Void
    let onClose: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(payload: payload)
    }

    func makeUIView(context: Context) -> WKWebView {
        let coordinator = context.coordinator
        coordinator.parent = self

        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.userContentController.add(coordinator, name: "SmarticoBridge")
        let web = WKWebView(frame: .zero, configuration: config)
        // the page detects the wrapper by user agent
        web.customUserAgent = SMTO_WRAPPER_UA
        web.isOpaque = false
        web.backgroundColor = .clear
        web.scrollView.backgroundColor = .clear
        web.scrollView.isScrollEnabled = false
        coordinator.webView = web

        // the popup wrapper gets its content injected (bcid 3), so no hash here
        let url = buildWrapperUrl(
            labelKey: Sdk.LABEL_KEY,
            brandKey: Sdk.BRAND_KEY,
            extUserId: Sdk.shared.extUserId,
            wrapper: WRAPPER_POPUP_URL
        )
        if let u = URL(string: url) { web.load(URLRequest(url: u)) }
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        context.coordinator.parent = self
    }

    static func dismantleUIView(_ web: WKWebView, coordinator: Coordinator) {
        web.configuration.userContentController.removeScriptMessageHandler(forName: "SmarticoBridge")
        web.stopLoading()
        coordinator.close()
    }

    /**
     * Bridge between the page and the SDK's PopupBridgeSession. The session
     * keeps its hooks (this coordinator) strongly and the coordinator keeps the
     * session, so `close()` drops the session to break that cycle.
     */
    final class Coordinator: NSObject, WKScriptMessageHandler, PopupSessionHooks {
        var parent: PopupWebView?
        weak var webView: WKWebView?
        private var session: PopupBridgeSession?
        private let payload: EngagementPayload

        init(payload: EngagementPayload) {
            self.payload = payload
            super.init()
            session = Smartico.createPopupSession(payload: payload, hooks: self)
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            let preview = (message.body as? String).map { String($0.prefix(160)) } ?? "\(message.body)"
            demoLog("popup bridge ← \(preview)")
            session?.handleMessage(body: message.body)
        }

        // ---- PopupSessionHooks ----

        func injectJs(_ js: String) {
            DispatchQueue.main.async { [weak self] in
                self?.webView?.evaluateJavaScript(js, completionHandler: nil)
            }
        }

        func onReadyToShow() {
            DispatchQueue.main.async { [weak self] in self?.parent?.onReadyToShow() }
        }

        func onClose() {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                let parent = self.parent
                self.close()
                parent?.onClose()
            }
        }

        /** Break the session ⇄ hooks cycle; the popup is done. */
        func close() {
            session = nil
            parent = nil
        }
    }
}
