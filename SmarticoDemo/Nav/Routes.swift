import Foundation
import SwiftUI

/**
 * Every destination of the demo — Nav.kt's `Routes`, as an enum so the
 * arguments are typed instead of packed into a path string. The four tab
 * roots (lobby · vip · inbox · profile) are routes too: navigating to one
 * switches tabs, exactly like `nav.navigate(Routes.VIP)` in the Android demo
 * lands on the VIP tab.
 */
enum Route: Hashable {
    case profile
    case missions
    case tournaments
    case games
    case inbox
    case levels
    case leaderboard
    case jackpots
    case raffles
    case store
    case widget(dp: String)
    case lobby
    case game(extId: String)
    case cashier
    case avatar
    case vip
    case tournament(instanceId: Int64)
    case raffle(raffleId: Int64)
    case draw(raffleId: Int64, drawId: Int64)

    /** The tab this route is the root of, if it is one. */
    var tab: AppTab? {
        switch self {
        case .lobby: return .lobby
        case .vip: return .vip
        case .inbox: return .inbox
        case .profile: return .profile
        default: return nil
        }
    }

    /** Game and widget run full-screen in the Android demo (no header, no bar). */
    var isFullScreen: Bool {
        switch self {
        case .widget, .game: return true
        default: return false
        }
    }
}

/**
 * RN-parity structure: the four TAB routes (Lobby · VIP · Inbox · Profile) get
 * the persistent header and the five-item bottom bar; feature screens are
 * pushed on top of the current tab with a plain back button and no bar.
 */
enum AppTab: Hashable, CaseIterable {
    case lobby, vip, inbox, profile

    var root: Route {
        switch self {
        case .lobby: return .lobby
        case .vip: return .vip
        case .inbox: return .inbox
        case .profile: return .profile
        }
    }
}

/**
 * The navigation state — Android's `NavHostController`. One stack of pushed
 * routes per tab (each tab is its own `NavigationStack`), plus the selected tab.
 *
 * Screens navigate with `AppRouter.shared.navigate(.missions)` (or the
 * `@EnvironmentObject var router: AppRouter` AppNav injects); the deep-link
 * bindings use the same calls, so a campaign CTA and a tap behave identically.
 */
@MainActor
final class AppRouter: ObservableObject {
    static let shared = AppRouter()

    @Published var tab: AppTab = .lobby
    @Published var paths: [AppTab: [Route]] = [.lobby: [], .vip: [], .inbox: [], .profile: []]

    private init() {}

    /** Open a destination: a tab root switches tabs, anything else is pushed onto the current tab. */
    func navigate(_ route: Route) {
        demoLog("navigate → \(route)")
        if let tab = route.tab {
            self.tab = tab
            paths[tab] = []
            return
        }
        paths[tab, default: []].append(route)
    }

    /** `popBackStack()`: drop the top pushed screen of the current tab. */
    func pop() {
        if !(paths[tab] ?? []).isEmpty { paths[tab]?.removeLast() }
    }

    func popToRoot() {
        paths[tab] = []
    }

    /** The route on screen: the top of the current tab's stack, else the tab root. */
    var current: Route {
        paths[tab]?.last ?? tab.root
    }

    /** True on a tab root — where the header and bottom bar are shown. */
    var atTabRoot: Bool {
        (paths[tab] ?? []).isEmpty
    }

    /** Binding for one tab's `NavigationStack(path:)`. */
    func path(for tab: AppTab) -> Binding<[Route]> {
        Binding(
            get: { self.paths[tab] ?? [] },
            set: { self.paths[tab] = $0 }
        )
    }

    /** User boundary (logout): every tab back to its root, Lobby selected. */
    func reset() {
        tab = .lobby
        for t in AppTab.allCases { paths[t] = [] }
    }
}
