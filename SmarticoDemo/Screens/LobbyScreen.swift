import SmarticoPublicAPI
import SwiftUI

/**
 * Casino lobby, mirroring the web fake-casino: a promo strip, the Top games
 * row, live missions and tournaments carousels, then the full game grid.
 *
 * On top sits the player card D1 wired to prove the event bridge end to end
 * (display name and points from the public props, balance from the demo
 * wallet); the missions and tournaments come from `Store`, so a server push
 * updates them here without a refetch of our own.
 */
struct LobbyScreen: View {
    @ObservedObject private var sdk = Sdk.shared
    @ObservedObject private var store = Store.shared
    @ObservedObject private var economy = Economy.shared
    @EnvironmentObject private var router: AppRouter

    private let top = casinoGames.filter { $0.categories.contains("Top") }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                LobbyPlayerCard(
                    name: sdk.identified ? sdk.displayName() : "Connecting…",
                    points: sdk.prop("ach_points_balance") ?? "—",
                    level: sdk.prop("ach_level_current"),
                    balance: economy.balance
                )
                .padding(.horizontal, 16)
                .padding(.top, 12)

                LobbySectionTitle(text: "Promotions")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        LobbyPromoTile(icon: "🎡", label: "Mini-games") { router.navigate(.games) }
                        LobbyPromoTile(icon: "💰", label: "Jackpots") { router.navigate(.jackpots) }
                        LobbyPromoTile(icon: "🏆", label: "Tournaments") { router.navigate(.tournaments) }
                        LobbyPromoTile(icon: "🎟️", label: "Raffles") { router.navigate(.raffles) }
                    }
                    .padding(.horizontal, 16)
                }

                LobbySectionTitle(text: "Top games")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(top, id: \.extId) { g in
                            LobbyGameTile(game: g, size: 120) { router.navigate(.game(extId: g.extId)) }
                        }
                    }
                    .padding(.horizontal, 16)
                }

                if !store.missions.isEmpty {
                    LobbySectionHeader(text: "Missions") { router.navigate(.missions) }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 10) {
                            // locked missions are teasers, not something to jump into
                            let visible = Array(store.missions.filter { $0.is_locked != true }.prefix(8))
                            ForEach(visible.indices, id: \.self) { i in
                                LobbyMissionCard(mission: visible[i]) { router.navigate(.missions) }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                } else if !store.loaded {
                    LobbySectionTitle(text: "Missions")
                    Meta("Loading missions…").padding(.horizontal, 16)
                }

                if !store.tournaments.isEmpty {
                    LobbySectionHeader(text: "Tournaments") { router.navigate(.tournaments) }
                    LobbyTournamentCarousel(tournaments: Array(store.tournaments.prefix(8))) { t in
                        router.navigate(.tournament(instanceId: t.instance_id ?? 0))
                    }
                }

                LobbySectionTitle(text: "All games")
                // a simple 3-column grid built from rows (the list is fixed and small)
                VStack(spacing: 10) {
                    ForEach(Array(stride(from: 0, to: casinoGames.count, by: 3)), id: \.self) { start in
                        HStack(alignment: .top, spacing: 10) {
                            ForEach(start..<start + 3, id: \.self) { i in
                                if i < casinoGames.count {
                                    let g = casinoGames[i]
                                    LobbyGameTile(game: g, size: nil) { router.navigate(.game(extId: g.extId)) }
                                        .frame(maxWidth: .infinity)
                                } else {
                                    Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 5)
            }
            .padding(.bottom, 24)
        }
        .onAppear {
            Store.shared.refreshMissions()
            Store.shared.refreshTournaments()
        }
    }
}

private struct LobbyPlayerCard: View {
    let name: String
    let points: String
    let level: String?
    let balance: Double

    var body: some View {
        Card {
            Meta("Welcome back")
            Text(name)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.white)
                .lineLimit(1)
                .padding(.top, 2)
            HStack(spacing: 18) {
                Figure(label: "Points", value: points, tone: .gold)
                Figure(label: "Balance", value: String(format: "€ %.2f", balance), tone: .good)
                if let level = level {
                    Figure(label: "Level", value: level, tone: .accent)
                }
            }
            .padding(.top, 12)
        }
    }

    private struct Figure: View {
        let label: String
        let value: String
        let tone: Color

        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                SectionLabel(label)
                Text(value)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(tone)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
    }
}

private struct LobbyPromoTile: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(icon).font(.system(size: 22))
                Text(label).font(.system(size: 13, weight: .bold)).foregroundColor(.white)
            }
            .frame(width: 140, height: 76)
            .background(Color.card)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }
}

/** A catalogue tile: the game's AVIF thumbnail with its name under it. */
private struct LobbyGameTile: View {
    let game: CasinoGame
    /** Fixed side for the Top row; nil fills the grid column as a square. */
    let size: CGFloat?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                art
                Text(game.name)
                    .font(.system(size: 11))
                    .foregroundColor(.white)
                    .lineLimit(1)
            }
        }
        .accessibilityLabel(game.name)
    }

    @ViewBuilder private var art: some View {
        // thumbnails are 720px; decode them at tile size (3x of a 120pt tile)
        let image = AvifImage(url: gameAsset(game.thumbnail), contentMode: .fill, maxPixelSize: 360)
            .background(Color.card)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        if let size = size {
            image.frame(width: size, height: size)
        } else {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay(image)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

/** One carousel card: fixed width so the row scrolls in even steps. */
private struct LobbyCard<Content: View>: View {
    let action: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) { content() }
                .frame(width: 144, alignment: .leading)
                .padding(8)
                .background(Color.card)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

private struct LobbyCardArt: View {
    let url: String?
    /** Tournament banners crop to the strip; square mission icons fit inside it. */
    var fill: Bool = true

    var body: some View {
        ZStack {
            Color.chromeBorder
            if let url = url, !url.isEmpty, let u = URL(string: url) {
                AsyncImage(url: u) { image in
                    image.resizable().aspectRatio(contentMode: fill ? .fill : .fit)
                } placeholder: {
                    Color.clear
                }
            }
        }
        .frame(width: 144, height: 70)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct LobbyCardName: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(.white)
            .lineLimit(1)
    }
}

private struct LobbyMissionCard: View {
    let mission: TMissionOrBadge
    let action: () -> Void

    var body: some View {
        let progress = mission.progress ?? 0
        let tasks = mission.tasks?.count ?? 0
        LobbyCard(action: action) {
            LobbyCardArt(url: mission.image, fill: false)
            LobbyCardName(text: stripHtml(mission.name)).padding(.top, 6)
            Text("\(Int(progress))%" + (tasks > 0 ? "  ·  \(tasks) task\(tasks > 1 ? "s" : "")" : ""))
                .font(.system(size: 10))
                .foregroundColor(.muted)
                .padding(.top, 2)
            ProgressBar(percent: progress, completed: mission.is_completed == true)
                .padding(.top, 6)
        }
    }
}

/**
 * The tournaments row. Its own view so the one-second countdown re-renders
 * these cards only, not the whole lobby.
 */
private struct LobbyTournamentCarousel: View {
    let tournaments: [TTournament]
    let onOpen: (TTournament) -> Void

    @StateObject private var clock = NowTicker()

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 10) {
                ForEach(tournaments.indices, id: \.self) { i in
                    card(tournaments[i])
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func card(_ t: TTournament) -> some View {
        let status = lobbyTournamentStatus(t)
        let live = t.is_in_progress == true || t.is_upcoming == true
        let target = t.is_in_progress == true ? t.end_time : t.start_time
        let prize = stripHtml(t.prize_pool_short)
        return LobbyCard(action: { onOpen(t) }) {
            ZStack(alignment: .top) {
                LobbyCardArt(url: t.image1)
                HStack {
                    if let status = status { Badge(label: status.label, tone: status.tone) }
                    Spacer()
                    if t.is_user_registered == true {
                        Text("✓").font(.system(size: 13, weight: .bold)).foregroundColor(.good)
                    }
                }
                .padding(4)
            }
            LobbyCardName(text: stripHtml(t.name)).padding(.top, 6)
            Text((prize.isEmpty ? "No prize" : prize) + "  ·  \(t.registration_count ?? 0) joined")
                .font(.system(size: 10))
                .foregroundColor(.muted)
                .lineLimit(1)
                .padding(.top, 2)
            Text(live && target != nil ? countdownShort(target!, now: clock.now) : status?.label ?? "—")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(live ? .accent : .muted)
                .padding(.top, 2)
        }
    }
}

/** Status pill for a tournament, matching the RN demo's tournamentStatus() (Details.kt). */
private func lobbyTournamentStatus(_ t: TTournament) -> (label: String, tone: Color)? {
    if t.is_cancelled == true { return ("Cancelled", .muted) }
    if t.is_finished == true { return ("Finished", .muted) }
    if t.is_in_progress == true { return ("Started", .good) }
    if t.is_upcoming == true { return ("Gathering", .accent) }
    return nil
}

private struct LobbySectionTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 17, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 8)
    }
}

/** Section title with a "View all ›" affordance, like the RN lobby. */
private struct LobbySectionHeader: View {
    let text: String
    let onViewAll: () -> Void

    var body: some View {
        HStack {
            Text(text).font(.system(size: 17, weight: .bold)).foregroundColor(.white)
            Spacer()
            Button(action: onViewAll) {
                Text("View all ›").font(.system(size: 12, weight: .bold)).foregroundColor(.accent)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }
}
