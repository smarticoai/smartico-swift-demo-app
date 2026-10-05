import SmarticoPublicAPI
import SwiftUI

/**
 * Tournament detail with the three tabs the web app has: leaderboard, prizes
 * and the description.
 * (Details.kt `TournamentDetailScreen`.)
 */
struct TournamentDetailScreen: View {
    let instanceId: Int64
    let onClose: () -> Void

    @State private var detail: TTournamentDetailed?
    @State private var error: String?
    @State private var tab = 0
    @State private var page = 1
    @State private var note: String?
    @State private var reload = 0
    @StateObject private var clock = NowTicker(active: false)

    var body: some View {
        let t = detail
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    Text(stripHtml(t?.name).nonEmpty ?? "Tournament")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let status = Self.tournamentStatus(t?.is_cancelled, t?.is_finished, t?.is_in_progress, t?.is_upcoming) {
                        Badge(label: status.0, tone: status.1)
                        Spacer().frame(width: 8)
                    }
                    Button(action: onClose) {
                        Text("✕").font(.system(size: 20)).foregroundColor(.muted)
                    }
                }
                if let error = error {
                    Meta(error)
                } else if let t = t {
                    content(t)
                } else {
                    Loading().frame(height: 240)
                }
            }
            .padding(16)
        }
        .task(id: reload) { await load() }
        .onChange(of: detail?.is_in_progress == true || detail?.is_upcoming == true) { clock.setActive($0) }
    }

    private func load() async {
        do {
            let d = try await Smartico.api.getTournamentInstanceInfo(tournamentInstanceId: instanceId)
            detail = d
            error = nil
            demoLog("tournament \(instanceId): \(stripHtml(d.name)) players=\(d.players?.count ?? 0) prizes=\(d.prizes?.count ?? 0) registered=\(d.is_user_registered == true) can_register=\(d.is_can_register == true)")
        } catch {
            // Campaign links often carry tournament_id where an instance_id
            // is expected — resolve it through the list and retry.
            let match = Store.shared.tournaments
                .first { $0.tournament_id == instanceId && $0.instance_id != instanceId }
            if let resolved = match?.instance_id {
                do {
                    detail = try await Smartico.api.getTournamentInstanceInfo(tournamentInstanceId: resolved)
                } catch {
                    self.error = "Tournament not found or no longer active."
                }
            } else {
                self.error = "Tournament not found or no longer active."
            }
        }
    }

    @ViewBuilder
    private func content(_ t: TTournamentDetailed) -> some View {
        let target = t.is_in_progress == true ? t.end_time : t.start_time
        if t.is_in_progress == true || t.is_upcoming == true, let target = target {
            Spacer().frame(height: 10)
            SectionLabel(Self.tournamentTimerLabel(t))
            Text(countdown(target, now: clock.now) ?? "—")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.accent)
        }
        Spacer().frame(height: 8)
        Meta(dateRange(t.start_time, t.end_time))

        Spacer().frame(height: 10)
        Card {
            HStack(alignment: .top, spacing: 10) {
                InfoCell(label: "Prize", value: stripHtml(t.prize_pool_short).nonEmpty ?? "No prize")
                InfoCell(label: "Registered", value: "\(t.registration_count ?? 0)/\(t.players_max_count.map { "\($0)" } ?? "∞")")
                InfoCell(label: "Buy in", value: Self.buyIn(t))
            }
        }

        Spacer().frame(height: 10)
        if t.is_user_registered == true {
            Meta("Registered ✓")
        } else if t.is_can_register == true {
            // The route id, unless it was a tournament_id resolved above.
            let id = t.instance_id ?? instanceId
            ActionButton(label: "Join Tournament", onResult: { note = $0; reload += 1 }) {
                let r = try await Smartico.api.registerInTournament(tournamentInstanceId: id)
                demoLog("registerInTournament(tournamentInstanceId: \(id)) → err_code=\(r.err_code.map { "\($0)" } ?? "nil") err_message=\(r.err_message ?? "nil")")
                return r.err_code == 0 ? "Registered ✓" : Self.registerError(r.err_code ?? -1, t.segment_dont_match_message)
            }
        } else {
            Meta("Registration closed")
        }
        if let note = note {
            Spacer().frame(height: 6)
            Meta(note)
        }

        Spacer().frame(height: 12)
        HStack(spacing: 8) {
            ForEach(Array(["Leaderboard", "Prizes", "More Info"].enumerated()), id: \.offset) { i, label in
                Button {
                    tab = i
                    page = 1
                } label: {
                    Text(label)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(tab == i ? .white : .muted)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(tab == i ? Color.accent : Color.card)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                }
            }
        }
        Spacer().frame(height: 12)

        switch tab {
        case 0: LeaderboardTab(players: t.players ?? [], page: page) { page = $0 }
        case 1: PrizesTab(prizes: t.prizes ?? [], page: page) { page = $0 }
        default: Meta(stripHtml(t.description).nonEmpty ?? "No description.")
        }

        let games = t.related_games ?? []
        if !games.isEmpty {
            Spacer().frame(height: 16)
            SectionLabel("Eligible games (\(games.count))")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(Array(games.enumerated()), id: \.offset) { _, g in
                        let meta = g.game_public_meta?.object
                        VStack(alignment: .leading, spacing: 0) {
                            Thumb(url: meta?["image"]?.string, size: 72)
                            Text(meta?["name"]?.string ?? "Game")
                                .font(.system(size: 10))
                                .foregroundColor(.muted)
                                .lineLimit(1)
                        }
                        .frame(width: 72, alignment: .leading)
                    }
                }
            }
        }
        Spacer().frame(height: 24)
    }
}

// ---------------------------------------------------------------------------
// Helpers. Nested in the screen type so they cannot collide with other files'
// top-level names (one module, four agents); TournamentsScreen reuses the
// status pill as `TournamentDetailScreen.tournamentStatus`.
// ---------------------------------------------------------------------------

extension TournamentDetailScreen {
    /** Status pill for a tournament, matching the RN demo's tournamentStatus(). */
    static func tournamentStatus(
        _ isCancelled: Bool?,
        _ isFinished: Bool?,
        _ isInProgress: Bool?,
        _ isUpcoming: Bool?
    ) -> (String, Color)? {
        if isCancelled == true { return ("Cancelled", .muted) }
        if isFinished == true { return ("Finished", .muted) }
        if isInProgress == true { return ("Started", .good) }
        if isUpcoming == true { return ("Gathering", .accent) }
        return nil
    }

    /** What the countdown above a tournament is counting towards. */
    static func tournamentTimerLabel(_ t: TTournamentDetailed) -> String {
        if t.is_in_progress == true { return "Finishing in" }
        if t.is_upcoming == true { return "Starts in" }
        if t.is_finished == true { return "Finished" }
        if t.is_cancelled == true { return "Cancelled" }
        return ""
    }

    /** registerInTournament err_code → a sentence a player can act on. */
    static func registerError(_ code: Int64, _ segmentMessage: String?) -> String {
        switch code {
        case 30002: return "Not enough balance to register."
        case 30003: return "Registration is not open right now."
        case 30004: return "You are already registered."
        case 30005: return segmentMessage ?? "You don't match the conditions for this tournament."
        case 30008: return "Tournament is full."
        default: return "Registration failed (code \(code))."
        }
    }

    static func buyIn(_ t: TTournamentDetailed) -> String {
        if (t.registration_cost_points ?? 0) > 0 { return "\(t.registration_cost_points ?? 0) pts" }
        if (t.registration_cost_gems ?? 0) > 0 { return "\(Int(t.registration_cost_gems ?? 0)) gems" }
        if (t.registration_cost_diamonds ?? 0) > 0 { return "\(Int(t.registration_cost_diamonds ?? 0)) 💎" }
        return "Free"
    }

    static let PER_PAGE = 8

    /** Kotlin's `getOrNull(i)`. */
    static func getOrNull<T>(_ list: [T], _ i: Int) -> T? {
        list.indices.contains(i) ? list[i] : nil
    }

    static func prizeRank(_ pr: TTournamentPrize) -> String {
        pr.place_from == pr.place_to
            ? "#\(Int(pr.place_from ?? 0))"
            : "#\(Int(pr.place_from ?? 0))–\(Int(pr.place_to ?? 0))"
    }

    static func prizeValue(_ pr: TTournamentPrize) -> String {
        pr.type == "POINTS_ADD" ? "\(pr.points ?? 0) pts" : "1 free spin"
    }

    fileprivate struct InfoCell: View {
        let label: String
        let value: String

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                SectionLabel(label)
                Text(value)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /** Top three on a podium, everyone else in a ranked table — as in the RN demo. */
    fileprivate struct LeaderboardTab: View {
        let players: [TTournamentPlayer]
        let page: Int
        let onPage: (Int) -> Void

        var body: some View {
            if players.isEmpty {
                Meta("No players registered.")
            } else {
                HStack(alignment: .bottom, spacing: 0) {
                    PodiumCell(p: TournamentDetailScreen.getOrNull(players, 1), place: 2)
                    PodiumCell(p: TournamentDetailScreen.getOrNull(players, 0), place: 1, big: true)
                    PodiumCell(p: TournamentDetailScreen.getOrNull(players, 2), place: 3)
                }
                let rest = Array(players.dropFirst(3))
                if !rest.isEmpty {
                    let per = TournamentDetailScreen.PER_PAGE
                    let pages = max(1, (rest.count + per - 1) / per)
                    let slice = Array(rest.dropFirst((page - 1) * per).prefix(per))
                    // the player always sees their own row, even when it is on another page
                    let meIndex = players.firstIndex { $0.is_me == true }
                    let appendMe = meIndex.flatMap { i in
                        i >= 3 && !slice.contains { $0.is_me == true } ? players[i] : nil
                    }

                    Spacer().frame(height: 10)
                    HStack(spacing: 0) {
                        Text("RANK").frame(width: 48, alignment: .leading)
                        Text("PLAYER").frame(maxWidth: .infinity, alignment: .leading)
                        Text("SCORE")
                    }
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.muted)
                    .padding(.bottom, 4)
                    ForEach(Array(slice.enumerated()), id: \.offset) { _, p in PlayerRow(p: p) }
                    if let me = appendMe { PlayerRow(p: me) }
                    if pages > 1 { Pager(page: page, pages: pages, onPage: onPage) }
                }
            }
        }
    }

    fileprivate struct PodiumCell: View {
        let p: TTournamentPlayer?
        let place: Int
        var big = false

        var body: some View {
            if let p = p {
                VStack(spacing: 0) {
                    ZStack(alignment: .bottomTrailing) {
                        PlayerAvatar(url: p.avatar_url, size: big ? 64 : 48)
                        PlaceBadge(place: place)
                    }
                    Text(stripHtml(p.public_username).nonEmpty ?? (p.user_ext_id ?? ""))
                        .font(.system(size: 11))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text(verbatim: "\(Int(p.scores ?? 0))")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.gold)
                }
                .padding(.bottom, big ? 12 : 0)
                .frame(maxWidth: .infinity)
            } else {
                Spacer().frame(maxWidth: .infinity)
            }
        }
    }

    fileprivate struct PlayerRow: View {
        let p: TTournamentPlayer

        var body: some View {
            HStack(spacing: 0) {
                Text(verbatim: "#\(p.position ?? 0)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.accent)
                    .frame(width: 44, alignment: .leading)
                PlayerAvatar(url: p.avatar_url, size: 28)
                Spacer().frame(width: 8)
                Text((stripHtml(p.public_username).nonEmpty ?? (p.user_ext_id ?? "")) + (p.is_me == true ? " (you)" : ""))
                    .font(.system(size: 12))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(verbatim: "\(Int(p.scores ?? 0))")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.gold)
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 4)
            .background(p.is_me == true ? Color.accent.opacity(0.18) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    fileprivate struct PlayerAvatar: View {
        let url: String?
        let size: CGFloat

        var body: some View {
            ZStack {
                Circle().fill(Color.chromeBorder)
                if let url = url, !url.isEmpty, let u = URL(string: url) {
                    AsyncImage(url: u) { $0.resizable().scaledToFill() } placeholder: { Color.clear }.allowsHitTesting(false).accessibilityHidden(true)
                } else {
                    Text("👤").font(.system(size: size * 0.4))
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
        }
    }

    fileprivate struct PlaceBadge: View {
        let place: Int

        var body: some View {
            Text(verbatim: "\(place)")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Color.accent)
                .clipShape(Capsule())
        }
    }

    fileprivate struct PrizesTab: View {
        let prizes: [TTournamentPrize]
        let page: Int
        let onPage: (Int) -> Void

        var body: some View {
            if prizes.isEmpty {
                Meta("No prizes added.")
            } else {
                HStack(alignment: .bottom, spacing: 0) {
                    PrizePodium(pr: TournamentDetailScreen.getOrNull(prizes, 1), place: 2)
                    PrizePodium(pr: TournamentDetailScreen.getOrNull(prizes, 0), place: 1)
                    PrizePodium(pr: TournamentDetailScreen.getOrNull(prizes, 2), place: 3)
                }
                let rest = Array(prizes.dropFirst(3))
                if !rest.isEmpty {
                    let per = TournamentDetailScreen.PER_PAGE
                    let pages = max(1, (rest.count + per - 1) / per)
                    Spacer().frame(height: 10)
                    ForEach(Array(rest.dropFirst((page - 1) * per).prefix(per).enumerated()), id: \.offset) { _, pr in
                        HStack(spacing: 0) {
                            Text(TournamentDetailScreen.prizeRank(pr))
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.accent)
                                .frame(width: 70, alignment: .leading)
                            Text(stripHtml(pr.name))
                                .font(.system(size: 12))
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(TournamentDetailScreen.prizeValue(pr))
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.gold)
                        }
                        .padding(.vertical, 4)
                    }
                    if pages > 1 { Pager(page: page, pages: pages, onPage: onPage) }
                }
            }
        }
    }

    fileprivate struct PrizePodium: View {
        let pr: TTournamentPrize?
        let place: Int

        var body: some View {
            if let pr = pr {
                VStack(spacing: 0) {
                    ZStack(alignment: .bottomTrailing) {
                        Thumb(url: pr.image_url, size: 56)
                        PlaceBadge(place: place)
                    }
                    Text(stripHtml(pr.name))
                        .font(.system(size: 11))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
            } else {
                Spacer().frame(maxWidth: .infinity)
            }
        }
    }

    fileprivate struct Pager: View {
        let page: Int
        let pages: Int
        let onPage: (Int) -> Void

        var body: some View {
            HStack(spacing: 6) {
                ForEach(1...pages, id: \.self) { n in
                    Button { onPage(n) } label: {
                        Text(verbatim: "\(n)")
                            .font(.system(size: 11))
                            .foregroundColor(n == page ? .white : .muted)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(n == page ? Color.accent : Color.card)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .disabled(n == page)
                }
            }
            .padding(.top, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
