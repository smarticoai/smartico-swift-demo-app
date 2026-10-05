import Foundation
import SmarticoPublicAPI
import UIKit

/**
 * Operator site paths → native screens. Mirrors the RN demo's tryOperatorUrl:
 * campaign links like https://play.smartico.ai/tournament-list must land on our
 * Tournaments screen, not in the browser. Unknown hosts/paths return false and
 * open externally.
 */
private let OPERATOR_HOSTS: Set<String> = ["play.smartico.ai"]

@MainActor
private func openOperatorUrl(_ nav: AppRouter, _ url: String) -> Bool {
    let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let re = try? NSRegularExpression(pattern: "^https?://([^/?#]+)([^?#]*)", options: [.caseInsensitive]),
          let m = re.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
          let hostRange = Range(m.range(at: 1), in: trimmed),
          let pathRange = Range(m.range(at: 2), in: trimmed)
    else { return false }
    if !OPERATOR_HOSTS.contains(trimmed[hostRange].lowercased()) { return false }
    let parts = trimmed[pathRange].split(separator: "/").map(String.init)
    let head = parts.first ?? ""
    let arg = parts.count > 1 ? parts[1] : nil
    switch head {
    case "": nav.navigate(.lobby)
    case "tournament-list": nav.navigate(.tournaments)
    case "tournament":
        if let id = arg.flatMap({ Int64($0) }) {
            nav.navigate(.tournament(instanceId: id))
        } else {
            nav.navigate(.tournaments)
        }
    case "missions": nav.navigate(.missions)
    case "mini-games": nav.navigate(.games)
    case "jackpots": nav.navigate(.jackpots)
    case "raffles": nav.navigate(.raffles)
    case "store": Smartico.dp("dp:gf_store&standalone=true")
    case "vip": nav.navigate(.vip)
    case "profile": nav.navigate(.profile)
    case "inbox": nav.navigate(.inbox)
    case "leaderboard": nav.navigate(.leaderboard)
    case "game":
        guard let arg = arg else { return false }
        nav.navigate(.game(extId: arg))
    case "cashier", "wallet-page": nav.navigate(.cashier)
    default: return false // unknown operator path → let the browser have it
    }
    return true
}

/**
 * Teach the SDK's deep-link router about THIS app's screens (MainActivity.kt's
 * `DpBindings`). The router calls these on the main thread — from a popup or
 * widget CTA, a server push, or `Smartico.dp` — hence `assumeIsolated`.
 */
private struct AppDpBindings: DpBindings {
    func openScreen(_ screen: DpScreen, _ dp: DeepLink) -> Bool {
        let route: Route
        switch screen {
        case .missions: route = .missions
        case .tournaments: route = .tournaments
        case .jackpots: route = .jackpots
        case .raffles: route = .raffles
        case .levels: route = .levels
        case .profile: route = .profile
        case .inbox: route = .inbox
        case .leaderboard: route = .leaderboard
        }
        demoLog("deep link \(dp.raw) → screen \(screen.rawValue)")
        MainActor.assumeIsolated { AppRouter.shared.navigate(route) }
        return true
    }

    /** Mini-games render in-app; other widget sections decline here. */
    func openWidget(_ dp: DeepLink) -> Bool {
        if !["gf_saw", "gf_section", "gf_quiz", "gf_matchx"].contains(dp.action) { return false }
        demoLog("deep link \(dp.raw) → in-app widget")
        MainActor.assumeIsolated { AppRouter.shared.navigate(.widget(dp: dp.raw)) }
        return true
    }

    /**
     * Campaign CTAs are usually authored for the WEB, as plain
     * links onto the operator's site. Opening those in a browser
     * throws the player out of the app onto the web version of
     * the same casino — so operator paths are mapped to our own
     * screens, and only unknown links leave the app.
     */
    func openUrl(_ url: String, target: String?) {
        MainActor.assumeIsolated {
            if openOperatorUrl(AppRouter.shared, url) {
                demoLog("deep link \(url) → operator path, in-app")
                return
            }
            demoLog("deep link \(url) → browser")
            if let u = URL(string: url) { UIApplication.shared.open(u) }
        }
    }
}

/**
 * Deep links into the app: the SDK router's bindings and custom handlers, plus
 * the external entry point `smartico-demo://dp?dp=<url-encoded dp>` — the iOS
 * stand-in for Android's `adb … --es dp "<link>"`:
 *
 *   xcrun simctl openurl booted "smartico-demo://dp?dp=dp%3Agf_missions"
 */
@MainActor
enum DeepLinks {
    private static var configured = false

    /** A link handed to the app before login: it runs as soon as a player is logged in. */
    private static var pendingEntryDp: String?

    /** DEBUG `-dp <link>` launch argument: runs once the user is identified. */
    private static var pendingLaunchDp: String?

    /** Wire the router once (Kotlin does it in `LaunchedEffect(nav)`). */
    static func configure() {
        if configured { return }
        configured = true
        DpRouter.debug = true // log deep links nothing handled, dev only

        Smartico.configureDp(AppDpBindings())

        // Our app's own deep links (fake-casino parity).
        _ = Smartico.registerDpHandler { dp in
            switch dp.action {
            case "deposit", "opencashier":
                MainActor.assumeIsolated { AppRouter.shared.navigate(.cashier) }
                return true
            default:
                return false
            }
        }

        // LAST RESORT (registered last): widget sections we do not render
        // natively — store, bonuses, clans… — open in the phone browser.
        // Any handler registered earlier wins over this one.
        _ = Smartico.registerDpHandler { dp in
            if !isWidgetAction(dp.action) { return false }
            let ext = MainActor.assumeIsolated { Sdk.shared.extUserId }
            if ext.isEmpty { return true }
            let url = buildWrapperUrl(
                labelKey: Sdk.LABEL_KEY,
                brandKey: Sdk.BRAND_KEY,
                extUserId: ext,
                hash: Sdk.demoHash(ext),
                dp: dp.raw
            )
            demoLog("deep link \(dp.raw) → widget in the browser")
            if let u = URL(string: url) {
                MainActor.assumeIsolated { UIApplication.shared.open(u) }
            }
            return true
        }

        #if DEBUG
        pendingLaunchDp = LaunchArgs.value(after: "-dp")
        #endif
    }

    /**
     * Deep-link entry point: a link handed to the app (OS URL, push tap,
     * `simctl openurl`) runs through the same router as campaign CTAs, so both
     * paths behave identically. Returns false for URLs that are not ours.
     */
    @discardableResult
    static func handleIncomingUrl(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "smartico-demo", url.host?.lowercased() == "dp" else { return false }
        let dp = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "dp" }?.value
        guard let dp = dp, !dp.isEmpty else {
            demoLog("incoming url without a dp: \(url.absoluteString)")
            return true
        }
        if Sdk.shared.loggedIn {
            run(dp, source: "url")
        } else {
            demoLog("incoming deep link parked until login: \(dp)")
            pendingEntryDp = dp
        }
        return true
    }

    /** A player just logged in: run a link that arrived before (Kotlin: `LaunchedEffect(loggedIn)`). */
    static func onLoggedIn() {
        guard let dp = pendingEntryDp else { return }
        pendingEntryDp = nil
        run(dp, source: "url")
    }

    /** The SDK identified the user: run the DEBUG `-dp` launch link, once. */
    static func onIdentified() {
        guard let dp = pendingLaunchDp else { return }
        pendingLaunchDp = nil
        run(dp, source: "launch argument")
    }

    private static func run(_ dp: String, source: String) {
        demoLog("deep link (\(source)) → \(dp)")
        let handled = Smartico.dp(dp)
        if !handled { demoLog("deep link not handled: \(dp)") }
    }
}
