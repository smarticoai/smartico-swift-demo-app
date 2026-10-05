import SmarticoPublicAPI
import SwiftUI
import WebKit

/**
 * Inbox.
 *
 * The LIST is native (getInboxMessages), but a message BODY is HTML authored in
 * the operator's backoffice — images, styling, links — so it is rendered in a
 * WebView rather than flattened to text. The WebView reports its own height
 * back, and link taps are handed to the deep-link router instead of navigating
 * inside the message.
 */
struct InboxScreen: View {
    @StateObject private var model = InboxModel()
    @ObservedObject private var sdk = Sdk.shared

    var body: some View {
        let visible = model.visible
        let unread = model.unread
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Inbox" + (unread > 0 ? "  (\(unread))" : ""))
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                if unread > 0 {
                    Button { model.markAllRead() } label: {
                        Text("Mark all read").font(.system(size: 12)).foregroundColor(.accent)
                    }
                    .accessibilityIdentifier("inbox-mark-all")
                }
            }
            .padding(.vertical, 12)

            HStack(spacing: 8) {
                InboxTab(label: "All", on: !model.favoritesOnly) { model.favoritesOnly = false }
                InboxTab(label: "★ Favorites", on: model.favoritesOnly) { model.favoritesOnly = true }
            }
            .padding(.bottom, 10)

            if model.loading && model.messages.isEmpty {
                Loading()
            } else if visible.isEmpty {
                Text("Nothing here yet.").foregroundColor(.muted)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(visible, id: \.message_guid) { m in
                            InboxRow(model: model, message: m)
                        }
                        // Paging is ours (the Kotlin screen shows the first page only):
                        // the server caps a page at 20 and this user has more than that.
                        if model.hasMore && !model.favoritesOnly {
                            Button { Task { await model.loadMore() } } label: {
                                Text(model.loadingMore ? "Loading…" : "Load more")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.accent)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                            }
                            .disabled(model.loadingMore)
                            .accessibilityIdentifier("inbox-load-more")
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Re-runs whenever the tab comes back on screen (Compose re-runs the
        // LaunchedEffect when the destination re-enters composition), and once
        // the user is identified when the screen was reached before that.
        .task(id: sdk.identified) {
            if sdk.identified { await model.load() }
        }
    }
}

/** One message: header row (tap = open/close, star = favourite) and, when open, the body. */
private struct InboxRow: View {
    @ObservedObject var model: InboxModel
    let message: TInboxMessage

    var body: some View {
        let m = message
        let guid = m.message_guid ?? ""
        let body = model.bodies[guid]
        let read = model.isRead(m)
        let fav = model.isFav(m)
        let preview = stripHtml(body?.preview_body)
        Card {
            HStack(alignment: .center, spacing: 0) {
                Button { model.toggleOpen(m) } label: {
                    HStack(alignment: .center, spacing: 0) {
                        if !read {
                            Text("●").font(.system(size: 12)).foregroundColor(.accent)
                            Spacer().frame(width: 6)
                        }
                        Thumb(url: body?.icon, size: 36)
                        if body?.icon?.isEmpty == false { Spacer().frame(width: 10) }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(stripHtml(body?.title).nonEmpty ?? "(no title)")
                                .font(.system(size: 14, weight: read ? .regular : .bold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            if !preview.isEmpty {
                                Text(preview)
                                    .font(.system(size: 12))
                                    .foregroundColor(.muted)
                                    .lineLimit(1)
                            }
                            Meta(m.sent_date ?? "")
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("inbox-row-\(guid)")

                Button { model.toggleFav(m) } label: {
                    Text(fav ? "★" : "☆")
                        .font(.system(size: 18))
                        .foregroundColor(fav ? .gold : .muted)
                        .padding(.leading, 8)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("inbox-fav-\(guid)")
            }

            if model.open == guid {
                VStack(alignment: .leading, spacing: 0) {
                    Spacer().frame(height: 10)
                    if let html = body?.html_body, !html.isEmpty {
                        InboxHtmlBody(html: html) { url in
                            model.reportClick(guid, url)
                        }
                    } else {
                        Meta(preview.nonEmpty ?? "—")
                    }
                    Spacer().frame(height: 8)
                    HStack(spacing: 8) {
                        // "Open" only when the CTA actually leads somewhere. Plain
                        // notifications carry `dp:close` (or ok/cancel), which the
                        // dp router treats as a no-op — a button that does nothing
                        // is worse than no button. The web inbox hides it the same way.
                        if let action = body?.action, inboxActionOpens(action) {
                            ActionButton(label: "Open") {
                                model.reportClick(guid, action)
                                Smartico.dp(action)
                                return ""
                            }
                            .accessibilityIdentifier("inbox-open-\(guid)")
                        }
                        ActionButton(label: "Delete") {
                            await model.delete(guid)
                            return ""
                        }
                        .accessibilityIdentifier("inbox-delete-\(guid)")
                    }
                }
                // Reported here rather than on tap: this branch is what puts the
                // message on screen, which is what an impression means.
                .onAppear { model.reportImpression(guid) }
            }
        }
    }
}

private struct InboxTab: View {
    let label: String
    let on: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(on ? .white : .muted)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(on ? Color.accent : Color.card)
                .clipShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
    }
}

// ---------------------------------------------------------------- state ----

/**
 * The screen's state (Kotlin keeps it in `remember`ed state holders; here it is
 * one ObservableObject so the rows can share it).
 */
@MainActor
final class InboxModel: ObservableObject {
    /** The server caps one getInboxMessages page at 20. */
    static let PAGE = 20

    /**
     * Bodies are immutable per message guid, so they are cached for the whole
     * session: coming back to the tab only re-reads the (cheap) envelope list.
     */
    private static var bodyCache: [String: TInboxMessageBody] = [:]

    @Published private(set) var messages: [TInboxMessage] = []
    @Published private(set) var bodies: [String: TInboxMessageBody] = InboxModel.bodyCache
    @Published private(set) var loading = true
    @Published private(set) var hasMore = false
    @Published private(set) var loadingMore = false
    @Published var favoritesOnly = false
    @Published var open: String?
    /** Total unread on the server (getInboxUnreadCount) — covers pages not loaded yet. */
    @Published private var serverUnread: Int64?
    // The mutations below don't refresh the list server-side, so local overlays
    // keep the UI honest until the next load.
    @Published private var readOverlay: [String: Bool] = [:]
    @Published private var favOverlay: [String: Bool] = [:]
    @Published private var deleted: Set<String> = []
    /**
     * Engagement analytics are per message, not per render: expanding the same
     * message twice is still one impression. Popups get this for free — their
     * wrapper page reports itself over the bridge — but an inbox body is our
     * own WebView, so the reporting is ours too.
     */
    private var impressed: Set<String> = []

    func isRead(_ m: TInboxMessage) -> Bool { readOverlay[m.message_guid ?? ""] ?? (m.read == true) }
    func isFav(_ m: TInboxMessage) -> Bool { favOverlay[m.message_guid ?? ""] ?? (m.favorite == true) }
    private func isDeleted(_ m: TInboxMessage) -> Bool { deleted.contains(m.message_guid ?? "") }

    var visible: [TInboxMessage] {
        messages
            .filter { !isDeleted($0) }
            .filter { !favoritesOnly || isFav($0) }
    }

    /**
     * Unread count for the title. The loaded pages are counted directly (Kotlin
     * does only that — it never pages); the server total covers the rest, minus
     * what was read or deleted here since the load.
     */
    var unread: Int {
        let loadedUnread = messages.filter { !isDeleted($0) && !isRead($0) }.count
        guard let server = serverUnread else { return loadedUnread }
        let changedHere = messages.filter { $0.read != true && (isDeleted($0) || readOverlay[$0.message_guid ?? ""] == true) }.count
        return max(loadedUnread, Int(server) - changedHere)
    }

    /** (Re)load the list — as many pages as were on screen — then the missing bodies. */
    func load() async {
        loading = true
        let want = max(InboxModel.PAGE, onServer)
        var fresh: [TInboxMessage] = []
        var lastPageFull = false
        do {
            while fresh.count < want {
                let page = try await Smartico.api.getInboxMessages(from: fresh.count, to: fresh.count + InboxModel.PAGE)
                fresh += page
                lastPageFull = page.count == InboxModel.PAGE
                if !lastPageFull { break }
            }
        } catch {
            demoLog("inbox: getInboxMessages failed: \(error)")
        }
        let unreadTotal = try? await Smartico.api.getInboxUnreadCount()
        #if DEBUG
        InboxModel.addHtmlSample(&fresh)
        #endif
        messages = fresh
        hasMore = lastPageFull
        serverUnread = unreadTotal
        // a fresh list already reflects every mutation sent before it
        readOverlay = [:]
        favOverlay = [:]
        deleted = []
        demoLog("inbox: getInboxMessages → \(fresh.count) messages (unread on server: \(unreadTotal.map { String($0) } ?? "?"), more: \(lastPageFull))")
        bodies = InboxModel.bodyCache
        // titles/previews live in the body payload, so the list needs them upfront
        await fetchBodies(fresh)
        loading = false
    }

    /** Messages the server still holds out of the loaded ones — the next page's offset. */
    private var onServer: Int {
        messages.filter { !isDeleted($0) && !InboxModel.isSample($0.message_guid ?? "") }.count
    }

    /** Next page. The offset skips messages deleted here — the server has dropped them already. */
    func loadMore() async {
        guard hasMore, !loadingMore else { return }
        loadingMore = true
        defer { loadingMore = false }
        let from = onServer
        do {
            let page = try await Smartico.api.getInboxMessages(from: from, to: from + InboxModel.PAGE)
            let known = Set(messages.compactMap { $0.message_guid })
            let added = page.filter { !known.contains($0.message_guid ?? "") }
            messages += added
            hasMore = page.count == InboxModel.PAGE
            demoLog("inbox: getInboxMessages(from: \(from)) → \(page.count) more (total \(messages.count))")
            await fetchBodies(added)
        } catch {
            demoLog("inbox: getInboxMessages(from: \(from)) failed: \(error)")
        }
    }

    /**
     * Each body is a plain HTTPS GET against the label's inbox CDN, so the
     * missing ones are fetched in parallel and shown as they arrive.
     */
    private func fetchBodies(_ list: [TInboxMessage]) async {
        let missing = list.compactMap { $0.message_guid }.filter { InboxModel.bodyCache[$0] == nil }
        if missing.isEmpty { return }
        var got = 0
        await withTaskGroup(of: (String, TInboxMessageBody?).self) { group in
            for guid in missing {
                group.addTask { (guid, try? await Smartico.api.getInboxMessageBody(messageGuid: guid)) }
            }
            for await (guid, body) in group {
                guard let body = body else { continue }
                got += 1
                InboxModel.bodyCache[guid] = body
                bodies[guid] = body
            }
        }
        let withHtml = missing.filter { bodies[$0]?.html_body?.isEmpty == false }.count
        let withAction = missing.filter { bodies[$0]?.action?.isEmpty == false }.count
        demoLog("inbox: getInboxMessageBody → \(got)/\(missing.count) bodies (html: \(withHtml), action: \(withAction))")
    }

    /** Tap on a row: open/close it, and the first open marks it read. */
    func toggleOpen(_ m: TInboxMessage) {
        let guid = m.message_guid ?? ""
        open = open == guid ? nil : guid
        if !isRead(m) {
            readOverlay[guid] = true
            Task {
                do {
                    let r = try await Smartico.api.markInboxMessageAsRead(messageGuid: guid)
                    demoLog("inbox: markInboxMessageAsRead(\(guid)) → err_code=\(r.err_code.map { String($0) } ?? "nil") err_message=\(r.err_message ?? "nil")")
                } catch {
                    demoLog("inbox: markInboxMessageAsRead(\(guid)) failed: \(error)")
                }
            }
        }
    }

    func toggleFav(_ m: TInboxMessage) {
        let guid = m.message_guid ?? ""
        let target = !isFav(m)
        favOverlay[guid] = target
        if InboxModel.isSample(guid) { return }
        Task {
            do {
                let r = try await Smartico.api.markUnmarkInboxMessageAsFavorite(messageGuid: guid, mark: target)
                demoLog("inbox: markUnmarkInboxMessageAsFavorite(\(guid), mark: \(target)) → err_code=\(r.err_code.map { String($0) } ?? "nil") err_message=\(r.err_message ?? "nil")")
            } catch {
                demoLog("inbox: markUnmarkInboxMessageAsFavorite(\(guid)) failed: \(error)")
            }
        }
    }

    func delete(_ guid: String) async {
        deleted.insert(guid)
        open = nil
        if InboxModel.isSample(guid) { return }
        do {
            let r = try await Smartico.api.deleteInboxMessage(messageGuid: guid)
            demoLog("inbox: deleteInboxMessage(\(guid)) → err_code=\(r.err_code.map { String($0) } ?? "nil") err_message=\(r.err_message ?? "nil")")
        } catch {
            demoLog("inbox: deleteInboxMessage(\(guid)) failed: \(error)")
        }
    }

    func markAllRead() {
        Task {
            do {
                let r = try await Smartico.api.markAllInboxMessagesAsRead()
                demoLog("inbox: markAllInboxMessagesAsRead → err_code=\(r.err_code.map { String($0) } ?? "nil")")
            } catch {
                demoLog("inbox: markAllInboxMessagesAsRead failed: \(error)")
            }
            for m in messages { if let guid = m.message_guid { readOverlay[guid] = true } }
            serverUnread = 0
        }
    }

    /** The body is on screen: one impression per message for the screen's lifetime. */
    func reportImpression(_ guid: String) {
        if InboxModel.isSample(guid) { return }
        if impressed.insert(guid).inserted {
            Smartico.api.reportImpressionEvent(engagement_uid: guid, activityType: ActivityTypeLimited.Inbox)
            demoLog("inbox: reportImpressionEvent(\(guid), Inbox)")
        }
    }

    /** A CTA or an in-body link was tapped — a click on the engagement, whatever it opens. */
    func reportClick(_ guid: String, _ action: String) {
        if InboxModel.isSample(guid) {
            demoLog("inbox: link tapped in the DEBUG sample (\(action)) — click not reported, no such engagement")
            return
        }
        Smartico.api.reportClickEvent(engagement_uid: guid, activityType: ActivityTypeLimited.Inbox, action: action)
        demoLog("inbox: reportClickEvent(\(guid), Inbox, \(action))")
    }
}

// ---------------------------------------------------------- DEBUG sample ----

extension InboxModel {
    /** Guid of the local sample message; never sent to the server. */
    static let SAMPLE_GUID = "debug-html-sample"

    static func isSample(_ guid: String) -> Bool { guid == SAMPLE_GUID }

    #if DEBUG
    /**
     * `-inboxHtmlSample` (DEBUG only): put one local message with an HTML body
     * on top of the list. The demo label's messages are all plain previews
     * (no `html_body`), so without it the WebView body below cannot be seen on
     * the simulator. It is marked read and its analytics are skipped — there is
     * no such engagement on the server.
     */
    static func addHtmlSample(_ list: inout [TInboxMessage]) {
        guard LaunchArgs.has("-inboxHtmlSample") else { return }
        list.insert(TInboxMessage(message_guid: SAMPLE_GUID, sent_date: "local sample", read: true, favorite: false), at: 0)
        bodyCache[SAMPLE_GUID] = TInboxMessageBody(
            title: "HTML body sample (DEBUG)",
            preview_body: "A local message with an html_body, rendered in a WKWebView",
            icon: "https://static4.smr.vc/b6e45cf4ae00002865d406-home-diamonds.webp",
            action: "dp:inbox",
            html_body: """
                <h3 style="margin:0 0 6px;color:#fff">Weekend reload 🎁</h3>
                <img src="https://static4.smr.vc/b6e45cf4ae00002865d406-home-diamonds.webp" style="width:96px">
                <p>Deposit this weekend and get <b>50 free spins</b>. The body is operator HTML:
                images, styling and links, measured by the page itself.</p>
                <ul><li>Links run through <code>Smartico.dp</code></li><li>Each tap is a click on the engagement</li></ul>
                <p><a href="dp:gf_missions">Open missions</a> · <a href="https://play.smartico.ai/tournament-list">Tournaments</a></p>
                """
        )
    }
    #endif
}

// ------------------------------------------------------------- html body ----

/**
 * Renders one message's HTML. The page measures itself and reports its height
 * back through a script message handler (a WebView has no intrinsic height
 * inside a scrolling list), and every link tap goes to the deep-link router —
 * so an operator link to, say, tournaments opens the native screen instead of
 * a browser.
 */
private struct InboxHtmlBody: View {
    let html: String
    let onLinkClick: (String) -> Void

    @State private var height: CGFloat = 60

    var body: some View {
        InboxHtmlWebView(html: html, height: $height, onLinkClick: onLinkClick)
            .frame(maxWidth: .infinity)
            .frame(height: height)
    }
}

private struct InboxHtmlWebView: UIViewRepresentable {
    let html: String
    @Binding var height: CGFloat
    let onLinkClick: (String) -> Void

    /** Not the popup bridge — this page only ever reports its height. */
    static let HANDLER = "SmarticoBody"

    static func document(_ html: String) -> String {
        """
        <!DOCTYPE html><html><head>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
          body{margin:0;padding:0;background:transparent;color:#d7d7ee;
               font-family:system-ui,sans-serif;font-size:14px;line-height:1.5;
               -webkit-text-size-adjust:100%}
          img{max-width:100%;height:auto;border-radius:8px}
          a{color:#9d86ff}
          table{max-width:100%}
        </style></head><body>\(html)</body></html>
        """
    }

    /** Images arrive after load, so re-measure a few times (and on every resize where supported). */
    static let MEASURE_JS = """
        (function(){
          function post(){ window.webkit.messageHandlers.\(HANDLER).postMessage(String(document.documentElement.scrollHeight)); }
          post(); setTimeout(post, 100); setTimeout(post, 500); setTimeout(post, 1500);
          if (window.ResizeObserver) { new ResizeObserver(post).observe(document.body); }
        })();
        """

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let coordinator = context.coordinator
        coordinator.parent = self

        let config = WKWebViewConfiguration()
        config.userContentController.add(coordinator, name: InboxHtmlWebView.HANDLER)
        let web = WKWebView(frame: .zero, configuration: config)
        web.isOpaque = false
        web.backgroundColor = .clear
        web.scrollView.backgroundColor = .clear
        // the list scrolls, not the message
        web.scrollView.isScrollEnabled = false
        web.scrollView.bounces = false
        web.scrollView.showsVerticalScrollIndicator = false
        web.allowsLinkPreview = false
        web.navigationDelegate = coordinator
        load(web, coordinator)
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        context.coordinator.parent = self
        if context.coordinator.loadedHtml != html { load(web, context.coordinator) }
    }

    private func load(_ web: WKWebView, _ coordinator: Coordinator) {
        coordinator.loadedHtml = html
        web.loadHTMLString(InboxHtmlWebView.document(html), baseURL: nil)
    }

    static func dismantleUIView(_ web: WKWebView, coordinator: Coordinator) {
        // the controller keeps its handler strongly — drop it so the coordinator can go
        web.configuration.userContentController.removeScriptMessageHandler(forName: HANDLER)
        web.navigationDelegate = nil
        web.stopLoading()
        coordinator.parent = nil
    }

    @MainActor
    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var parent: InboxHtmlWebView?
        var loadedHtml: String?

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let h = Double("\(message.body)"), h > 0 else { return }
            let clamped = CGFloat(min(max(h, 40), 2400))
            if let parent = parent, parent.height != clamped { parent.height = clamped }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
        ) {
            // The document itself (loadHTMLString → about:blank) and sub-frames
            // (embedded media) load normally; a nil target frame is a
            // target="_blank" link, which is a tap like any other.
            let mainFrame = navigationAction.targetFrame?.isMainFrame ?? true
            guard let url = navigationAction.request.url, mainFrame,
                  url.scheme != "about", url.scheme != "data"
            else {
                decisionHandler(.allow)
                return
            }
            decisionHandler(.cancel)
            let raw = url.absoluteString
            // A link inside the body is a click on the engagement,
            // whatever it turns out to open.
            parent?.onLinkClick(raw)
            Smartico.dp(raw) // operator links land on native screens
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript(InboxHtmlWebView.MEASURE_JS, completionHandler: nil)
        }
    }
}

/** Does this inbox CTA go anywhere? `dp:close` / `ok` / `cancel` are engagement-tracking no-ops. */
private func inboxActionOpens(_ action: String) -> Bool {
    let a = parseDp(action).action
    if a.isEmpty { return false }
    return !["ok", "cancel", "close", "close_me", "gf_close"].contains(a)
}
