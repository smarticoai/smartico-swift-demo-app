import SmarticoPublicAPI
import SwiftUI

/**
 * Tournament lobby (Screens.kt `TournamentsScreen`).
 *
 * Tiles, like the RN demo: artwork carries the tournament, the badge carries
 * its state, and the line underneath counts down while it is live.
 */
struct TournamentsScreen: View {
    @ObservedObject private var store = Store.shared
    @StateObject private var clock = NowTicker()

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10, alignment: .top), count: 3)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Tournaments")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.vertical, 12)
                if store.tournaments.isEmpty && !store.loaded {
                    Loading().frame(height: 240)
                } else if store.tournaments.isEmpty {
                    Text("Nothing here yet.").foregroundColor(.muted)
                } else {
                    // three per row; the last row's tiles keep the width of a full one
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(Array(store.tournaments.enumerated()), id: \.offset) { _, t in
                            TournamentTile(t: t, now: clock.now) {
                                AppRouter.shared.navigate(.tournament(instanceId: t.instance_id ?? 0))
                            }
                        }
                    }
                }
                Spacer().frame(height: 16)
            }
            .padding(.horizontal, 16)
        }
        .onAppear {
            Store.shared.refreshTournaments()
            if !store.tournaments.isEmpty { Self.log(store.tournaments) }
        }
        .onChange(of: store.tournaments) { Self.log($0) }
    }

    /** One evidence line per list: `instance_id:status[✓ registered][+reg can register]`. */
    private static func log(_ list: [TTournament]) {
        demoLog("tournaments: \(list.count) — " + list.map { t in
            let status = TournamentDetailScreen.tournamentStatus(t.is_cancelled, t.is_finished, t.is_in_progress, t.is_upcoming)?.0 ?? "-"
            return "\(t.instance_id ?? 0):\(status)\(t.is_user_registered == true ? "✓" : "")\(t.is_can_register == true ? "+reg" : "")"
        }.joined(separator: " "))
    }
}

private extension TournamentsScreen {
    struct TournamentTile: View {
        let t: TTournament
        let now: Int64
        let onClick: () -> Void

        var body: some View {
            let status = TournamentDetailScreen.tournamentStatus(t.is_cancelled, t.is_finished, t.is_in_progress, t.is_upcoming)
            let live = t.is_in_progress == true || t.is_upcoming == true
            // a running tournament counts down to its end, a gathering one to its start
            let target = t.is_in_progress == true ? t.end_time : t.start_time

            Button(action: onClick) {
                VStack(alignment: .leading, spacing: 0) {
                    Color.chromeBorder
                        .aspectRatio(1, contentMode: .fit)
                        .overlay(
                            Group {
                                if let image = t.image1, let u = URL(string: image) {
                                    AsyncImage(url: u) { $0.resizable().scaledToFill() } placeholder: { Color.clear }.allowsHitTesting(false).accessibilityHidden(true)
                                }
                            }
                        )
                        .clipped()
                        .overlay(alignment: .topLeading) {
                            if let status = status {
                                Badge(label: status.0, tone: status.1).padding(5)
                            }
                        }
                        .overlay(alignment: .topTrailing) {
                            if t.is_user_registered == true {
                                Text("✓")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.good)
                                    .padding(5)
                            }
                        }
                    VStack(alignment: .leading, spacing: 0) {
                        Text(stripHtml(t.name))
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Text(live && target != nil ? countdownShort(target ?? 0, now: now) : status?.0 ?? "—")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(live ? .accent : .muted)
                    }
                    .padding(8)
                }
                .background(Color.card)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                // the cover art overflows its square before clipping; keep taps inside the tile
                .contentShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
    }
}
