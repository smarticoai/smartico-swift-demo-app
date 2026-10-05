import SmarticoPublicAPI
import SwiftUI
import WebKit

/**
 * Hosts a Smartico widget deep link (mini-games) in a WebView.
 *
 * The page identifies itself from the URL and runs the deep link; the SDK's
 * WidgetBridgeSession handles the whole postMessage conversation, so this
 * screen only supplies the WebView, a loader and what "close"/"navigate"
 * should do.
 */
struct WidgetScreen: View {
    let dp: String
    let onClose: () -> Void

    @State private var ready = false
    /**
     * Built once per dp (Kotlin: `remember(currentDp)`): the identify hash
     * embeds a timestamp, so rebuilding it on every render would change the
     * url and reload the page each time.
     */
    @State private var url: String

    init(dp: String, onClose: @escaping () -> Void) {
        self.dp = dp
        self.onClose = onClose
        _url = State(initialValue: WidgetScreen.wrapperUrl(dp))
    }

    private static func wrapperUrl(_ dp: String) -> String {
        let ext = Sdk.shared.extUserId
        return buildWrapperUrl(
            labelKey: Sdk.LABEL_KEY,
            brandKey: Sdk.BRAND_KEY,
            extUserId: ext,
            base: Sdk.shared.prop("native_app_gf_url"), // server-built URL when identify supplied one
            hash: Sdk.demoHash(ext),
            dp: dp
        )
    }

    var body: some View {
        ZStack {
            WidgetWebView(
                url: url,
                onReady: { ready = true },
                onClose: onClose,
                onNavigateInWidget: { dpRaw in
                    // in-widget flows (respin offers, section jumps) stay inside
                    ready = false
                    url = WidgetScreen.wrapperUrl(dpRaw)
                }
            )
            .ignoresSafeArea(edges: .bottom)
            if !ready {
                Text("Loading game…").foregroundColor(.muted)
            }
        }
        .background(Color.bg)
    }
}

/** The WKWebView behind `WidgetScreen`; reloads when the url changes. */
private struct WidgetWebView: UIViewRepresentable {
    let url: String
    let onReady: () -> Void
    let onClose: () -> Void
    let onNavigateInWidget: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let coordinator = context.coordinator
        coordinator.parent = self

        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        // the page posts bridge messages to window.webkit.messageHandlers.SmarticoBridge
        config.userContentController.add(coordinator, name: "SmarticoBridge")
        let web = WKWebView(frame: .zero, configuration: config)
        // the page detects the wrapper by user agent
        web.customUserAgent = SMTO_WRAPPER_UA
        web.isOpaque = false
        web.backgroundColor = .clear
        coordinator.webView = web
        load(web, coordinator)
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        context.coordinator.parent = self
        if context.coordinator.loadedUrl != url { load(web, context.coordinator) }
    }

    private func load(_ web: WKWebView, _ coordinator: Coordinator) {
        coordinator.loadedUrl = url
        if let u = URL(string: url) { web.load(URLRequest(url: u)) }
    }

    static func dismantleUIView(_ web: WKWebView, coordinator: Coordinator) {
        web.configuration.userContentController.removeScriptMessageHandler(forName: "SmarticoBridge")
        web.stopLoading()
        coordinator.close()
    }

    /**
     * Bridge between the page and the SDK's WidgetBridgeSession. The session
     * keeps its hooks (this coordinator) strongly and the coordinator keeps the
     * session, so `close()` drops the session to break that cycle.
     */
    final class Coordinator: NSObject, WKScriptMessageHandler, WidgetSessionHooks {
        var parent: WidgetWebView?
        weak var webView: WKWebView?
        var loadedUrl: String?
        private var session: WidgetBridgeSession?

        override init() {
            super.init()
            session = Smartico.createWidgetSession(hooks: self)
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            session?.handleMessage(body: message.body)
        }

        // ---- WidgetSessionHooks ----

        func onReady() {
            DispatchQueue.main.async { [weak self] in self?.parent?.onReady() }
        }

        func onClose() {
            DispatchQueue.main.async { [weak self] in self?.parent?.onClose() }
        }

        func onNavigateInWidget(_ dpRaw: String) {
            DispatchQueue.main.async { [weak self] in self?.parent?.onNavigateInWidget(dpRaw) }
        }

        /** Break the session ⇄ hooks cycle; the screen is gone. */
        func close() {
            session = nil
            parent = nil
        }
    }
}
