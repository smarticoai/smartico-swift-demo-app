import SmarticoPublicAPI
import SwiftUI
import UIKit

/**
 * App chrome and navigation host (Nav.kt + Chrome.kt), RN-parity structure:
 * the four TAB routes (Lobby · VIP · Inbox · Profile) get the persistent
 * header and the five-item bottom bar (Menu · VIP · Promos · Inbox · Profile);
 * feature screens are pushed on top of the current tab with a plain back
 * button and no bar. The Lobby has no bar item — it is reached through the
 * logo or the burger, exactly like the original fake-casino.
 *
 * Each tab is its own NavigationStack inside a TabView whose system tab bar is
 * hidden (the bottom bar below replaces it), so every tab keeps its own stack.
 * Game and widget run full-screen, as in the Android demo: no header, no bar,
 * no navigation bar — the slot draws its own "‹ Back" and the widget page its
 * own ✕ (Route.isFullScreen).
 */
struct AppNav: View {
    @ObservedObject private var router = AppRouter.shared
    @State private var burgerOpen = false
    @State private var promosOpen = false

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                TabView(selection: $router.tab) {
                    ForEach(AppTab.allCases, id: \.self) { tab in
                        TabStack(tab: tab)
                            .tag(tab)
                            .toolbar(.hidden, for: .tabBar)
                    }
                }
                if router.atTabRoot {
                    BottomBar(
                        promosOpen: promosOpen,
                        onPromos: { withAnimation(.easeOut(duration: 0.2)) { promosOpen.toggle() } },
                        onMenu: { withAnimation(.easeOut(duration: 0.2)) { burgerOpen = true } }
                    )
                }
            }
            // drawn over everything, including the bar
            BurgerMenu(visible: $burgerOpen)
        }
        .background(Color.bg.ignoresSafeArea())
        .environmentObject(router)
        .onChange(of: router.atTabRoot) { atRoot in if !atRoot { promosOpen = false } }
    }
}

/** One tab: its root screen under the header, and the routes pushed on top of it. */
private struct TabStack: View {
    let tab: AppTab
    @ObservedObject private var router = AppRouter.shared

    var body: some View {
        NavigationStack(path: router.path(for: tab)) {
            VStack(spacing: 0) {
                AppHeader()
                RouteView(route: tab.root)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color.bg.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Route.self) { route in
                if route.isFullScreen {
                    RouteView(route: route)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.bg.ignoresSafeArea())
                        .toolbar(.hidden, for: .navigationBar)
                        .background(EdgeSwipeBack())
                } else {
                    // feature screens: a plain back button and no bar (Chrome.kt's BackRow)
                    RouteView(route: route)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.bg.ignoresSafeArea())
                        .navigationTitle("")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbarBackground(Color.chromeBg, for: .navigationBar)
                        .toolbarBackground(.visible, for: .navigationBar)
                        .toolbarColorScheme(.dark, for: .navigationBar)
                }
            }
        }
    }
}

/**
 * Hiding the navigation bar also switches off UIKit's edge-swipe "back". On
 * Android the full-screen routes still have the system back as a way out —
 * which matters when a widget page never loads and so never shows its own ✕ —
 * so the swipe is re-armed for them here.
 */
private struct EdgeSwipeBack: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) {}

    final class Controller: UIViewController {
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            guard let pop = navigationController?.interactivePopGestureRecognizer else { return }
            pop.delegate = EdgeSwipeDelegate.shared
            pop.isEnabled = true
        }
    }
}

/** Lets the pop gesture begin whenever something is pushed, bar or no bar. */
private final class EdgeSwipeDelegate: NSObject, UIGestureRecognizerDelegate {
    static let shared = EdgeSwipeDelegate()

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        // the recognizer lives on the navigation controller's own view
        guard let nav = gestureRecognizer.view?.next as? UINavigationController else { return false }
        return nav.viewControllers.count > 1
    }
}

/** Route → screen (Nav.kt's NavHost). `onClose` pops the current tab's stack. */
struct RouteView: View {
    let route: Route

    var body: some View {
        let router = AppRouter.shared
        let pop: () -> Void = { router.pop() }
        switch route {
        case .lobby: LobbyScreen()
        case .cashier: CashierScreen(onClose: pop)
        case .game(let extId): GameScreen(extId: extId, onClose: pop)
        case .profile: ProfileScreen()
        case .missions: MissionsScreen()
        case .tournaments: TournamentsScreen()
        case .games: MiniGamesScreen()
        case .inbox: InboxScreen()
        case .levels: LevelsScreen()
        case .vip: VipScreen()
        case .avatar: AvatarPickerScreen(onClose: pop)
        case .tournament(let instanceId):
            TournamentDetailScreen(instanceId: instanceId, onClose: pop)
        case .raffle(let raffleId):
            RaffleDrawsScreen(
                raffleId: raffleId,
                onClose: pop,
                onOpenDraw: { drawId in router.navigate(.draw(raffleId: raffleId, drawId: drawId)) }
            )
        case .draw(let raffleId, let drawId):
            DrawDetailScreen(raffleId: raffleId, drawId: drawId, onClose: pop)
        case .leaderboard: LeaderboardScreen()
        case .jackpots: JackpotsScreen()
        case .raffles: RafflesScreen()
        case .store: StoreScreen()
        case .widget(let dp): WidgetScreen(dp: dp, onClose: pop)
        }
    }
}

// ---------------------------------------------------------------- header ----

struct AppHeader: View {
    @ObservedObject private var sdk = Sdk.shared
    @ObservedObject private var economy = Economy.shared
    @ObservedObject private var router = AppRouter.shared

    var body: some View {
        HStack(spacing: 8) {
            Button { router.navigate(.lobby) } label: {
                Text("🎰 Fakebet")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .fixedSize()
            }
            Spacer(minLength: 4)
            Stat(text: "🟡 \(sdk.prop("ach_points_balance") ?? "—")")
            Stat(text: String(format: "€ %.2f", economy.balance))
                .accessibilityIdentifier("header-balance")
            Button { router.navigate(.cashier) } label: {
                Text("Deposit")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 9))
            }
            Button { router.navigate(.profile) } label: {
                ZStack {
                    Circle().fill(Color.chromeBorder)
                    if let url = sdk.avatarUrl(), let u = URL(string: url) {
                        AsyncImage(url: u) { $0.resizable().scaledToFill() } placeholder: { Text("👤").font(.system(size: 14)) }
                    } else {
                        Text("👤").font(.system(size: 14))
                    }
                }
                .frame(width: 30, height: 30)
                .clipShape(Circle())
            }
            .accessibilityLabel("Profile avatar")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.chromeBg.ignoresSafeArea(edges: .top))
    }
}

private struct Stat: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.card)
            .clipShape(RoundedRectangle(cornerRadius: 9))
    }
}

// ------------------------------------------------------------ bottom bar ----

struct BottomBar: View {
    let promosOpen: Bool
    let onPromos: () -> Void
    let onMenu: () -> Void

    @ObservedObject private var sdk = Sdk.shared
    @ObservedObject private var router = AppRouter.shared

    var body: some View {
        let unread = Int(sdk.prop("core_inbox_unread_count").flatMap { Double($0) } ?? 0)
        VStack(spacing: 0) {
            // Promos spread — fake-casino's popping circles, simplified like in RN
            if promosOpen {
                HStack(spacing: 14) {
                    SpreadButton(icon: "🏆", label: "Tournaments") { onPromos(); router.navigate(.tournaments) }
                    SpreadButton(icon: "🎯", label: "Missions") { onPromos(); router.navigate(.missions) }
                    SpreadButton(icon: "🎡", label: "Mini-games") { onPromos(); router.navigate(.games) }
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 10)
                .transition(.opacity.combined(with: .offset(y: 28)))
            }
            HStack(spacing: 0) {
                BarItem(icon: "☰", label: "Menu", active: false, action: onMenu)
                BarItem(icon: "👑", label: "VIP", active: router.tab == .vip) { router.navigate(.vip) }
                BarItem(icon: promosOpen ? "✕" : "🎁", label: "Promos", active: promosOpen, action: onPromos)
                BarItem(icon: "📬", label: "Inbox", active: router.tab == .inbox, badge: unread) { router.navigate(.inbox) }
                BarItem(icon: "👤", label: "Profile", active: router.tab == .profile) { router.navigate(.profile) }
            }
            .padding(.vertical, 8)
            .background(Color.chromeBg.ignoresSafeArea(edges: .bottom))
        }
    }
}

private struct BarItem: View {
    let icon: String
    let label: String
    let active: Bool
    var badge: Int = 0
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                ZStack(alignment: .topTrailing) {
                    Text(icon).font(.system(size: 18)).foregroundColor(active ? .accent : .muted)
                    if badge > 0 {
                        Text(badge > 99 ? "99+" : "\(badge)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .offset(x: 12, y: -4)
                    }
                }
                Text(label)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(active ? .accent : .muted)
            }
            .frame(maxWidth: .infinity)
        }
        .accessibilityLabel(badge > 0 ? "\(label), \(badge) unread" : label)
    }
}

private struct SpreadButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(icon).font(.system(size: 22))
                Text(label).font(.system(size: 10, weight: .bold)).foregroundColor(.white)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.card)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }
}

// ---------------------------------------------------------------- burger ----

private struct MenuItem: Identifiable {
    let icon: String
    let label: String
    var route: Route? = nil
    var disabled: Bool = false
    var id: String { label }
}

// The RN demo disables Store (no native screen there); this demo has one.
private let MENU_ITEMS: [MenuItem] = [
    MenuItem(icon: "🎰", label: "Casino", route: .lobby),
    MenuItem(icon: "⚽", label: "Sports — coming soon", disabled: true),
    MenuItem(icon: "🎯", label: "Missions", route: .missions),
    MenuItem(icon: "🏆", label: "Tournaments", route: .tournaments),
    MenuItem(icon: "🎟️", label: "Raffles", route: .raffles),
    MenuItem(icon: "💰", label: "Jackpots", route: .jackpots),
    MenuItem(icon: "🛍️", label: "Store", route: .store),
    MenuItem(icon: "🎡", label: "Mini-games", route: .games),
    MenuItem(icon: "🥇", label: "Leaderboard", route: .leaderboard),
    MenuItem(icon: "👑", label: "VIP", route: .vip),
]

/** The fake-casino burger drawer: section links + reset progress + logout. */
struct BurgerMenu: View {
    @Binding var visible: Bool
    @State private var confirmReset = false

    var body: some View {
        ZStack(alignment: .leading) {
            if visible {
                Color.black.opacity(0.6)
                    .ignoresSafeArea()
                    .onTapGesture { close() } // tap outside closes
                    .transition(.opacity)
                drawer
                    .transition(.move(edge: .leading))
            }
        }
        .alert("Reset progress", isPresented: $confirmReset) {
            Button("Reset", role: .destructive) {
                close()
                Task {
                    let msg = await Sdk.shared.resetProgress()
                    demoLog("reset progress: \(msg)")
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Start over as a fresh player? Points, levels and missions will reset.")
        }
    }

    private var drawer: some View {
        GeometryReader { geo in
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("🎰 Fakebet").font(.system(size: 20, weight: .bold)).foregroundColor(.white)
                    Spacer()
                    Button { close() } label: { Text("✕").font(.system(size: 20)).foregroundColor(.muted) }
                }
                .padding(.vertical, 16)

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(MENU_ITEMS) { item in
                            Button {
                                close()
                                if let route = item.route { AppRouter.shared.navigate(route) }
                            } label: {
                                HStack(spacing: 12) {
                                    Text(item.icon).font(.system(size: 18))
                                    Text(item.label)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(item.disabled ? .muted : .white)
                                    Spacer()
                                }
                                .padding(.vertical, 13)
                                .contentShape(Rectangle())
                            }
                            .disabled(item.disabled)
                        }
                    }
                }

                Button { confirmReset = true } label: {
                    Text("♻️ Reset progress").font(.system(size: 14, weight: .bold)).foregroundColor(.white)
                }
                .padding(.vertical, 10)
                Button {
                    close()
                    Sdk.shared.logout()
                } label: {
                    Text("Log out").font(.system(size: 14, weight: .bold)).foregroundColor(Color(hex: 0xFF8F8F))
                }
                .padding(.vertical, 10)
                .padding(.bottom, 12)
            }
            .padding(.horizontal, 18)
            .frame(width: geo.size.width * 0.78, alignment: .leading)
            .frame(maxHeight: .infinity)
            .background(Color.bg.ignoresSafeArea())
        }
    }

    private func close() {
        withAnimation(.easeOut(duration: 0.2)) { visible = false }
    }
}
