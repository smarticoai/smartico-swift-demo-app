import SmarticoPublicAPI
import SwiftUI

/**
 * Raffle draws + draw detail, ported from the RN demo (screens/raffles/).
 * A raffle owns several DRAWS (regular / recurring 🔁 / grand 🏆); each draw
 * owns prizes and past RUNS. Tickets are earned elsewhere (missions, spins) —
 * these screens show odds, unlock progress, run history and prize claiming.
 * (Raffles.kt `RaffleDrawsScreen`; the draw detail is DrawDetailScreen.swift.)
 */
struct RaffleDrawsScreen: View {
    let raffleId: Int64
    let onClose: () -> Void
    let onOpenDraw: (Int64) -> Void

    @State private var draws: [TRaffleDraw] = []
    @State private var name = "Raffle"
    @State private var tickets = ""
    @StateObject private var clock = NowTicker()
    @ObservedObject private var sdk = Sdk.shared

    var body: some View {
        let myAvatar = sdk.avatarUrl()
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    Text(name.nonEmpty ?? "Raffle")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button(action: onClose) {
                        Text("✕").font(.system(size: 20)).foregroundColor(.muted)
                    }
                }
                Meta("\(tickets) · \(draws.count) draws")
                Spacer().frame(height: 10)

                ForEach(Array(draws.enumerated()), id: \.offset) { _, d in
                    Button { onOpenDraw(d.id ?? 0) } label: {
                        DrawRow(d: d, now: clock.now, myAvatar: myAvatar)
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 10)
                }
            }
            .padding(16)
        }
        .task(id: raffleId) {
            let raffle = (try? await Smartico.api.getRaffles())?.first { $0.id == raffleId }
            name = stripHtml(raffle?.name)
            tickets = "Tickets \(raffle?.current_tickets_count ?? 0)/\(raffle?.max_tickets_count ?? 0)"
            // active draws first (soonest execution first); executed pushed to the end
            draws = (raffle?.draws ?? []).sorted {
                let a = (Self.isTerminal($0) ? 1 : 0, $0.execution_ts ?? 0)
                let b = (Self.isTerminal($1) ? 1 : 0, $1.execution_ts ?? 0)
                return a < b
            }
            demoLog("raffle \(raffleId) draws: \(draws.count) — " + draws.map { d in
                "\(d.id ?? 0):\(stripHtml(d.name)) state=\(d.current_state ?? 0) run=\(d.run_id ?? 0) total=\(d.total_tickets_count ?? 0) mine=\(d.my_tickets_count ?? 0) optin=\(d.requires_optin == true ? (d.user_opted_in == true ? "in" : "required") : "auto")"
            }.joined(separator: " | "))
        }
    }
}

// ---------------------------------------------------------------------------
// Helpers, shared with DrawDetailScreen as `RaffleDrawsScreen.x`. Nested in the
// screen type so they cannot collide with other files' top-level names.
// ---------------------------------------------------------------------------

extension RaffleDrawsScreen {
    // TRaffleDraw.current_state / execution_type — taken from the SDK so they
    // cannot drift out of sync with the server's numbering.
    static let STATE_OPEN = RaffleDrawInstanceState.Open
    static let STATE_WINNER_SELECTION = RaffleDrawInstanceState.WinnerSelection
    static let STATE_EXECUTED = RaffleDrawInstanceState.Executed
    static let STATE_CANCELLED = RaffleDrawInstanceState.Cancelled

    /** A draw that will never run again: nothing to count down to. */
    static func isTerminal(_ d: TRaffleDraw) -> Bool {
        d.current_state == STATE_EXECUTED || d.current_state == STATE_CANCELLED
    }

    /** k/m abbreviation, matching the web demo's formatNumber. */
    static func formatNumber(_ n: Int64?) -> String {
        let v = n ?? 0
        if v >= 10_000_000 { return "\(v / 1_000_000)m" }
        if v >= 1_000_000 { return "\(Double(v / 100_000) / 10.0)m" }
        if v >= 10_000 { return "\(v / 1_000)k" }
        if v >= 1_000 { return "\(Double(v / 100) / 10.0)k" }
        return "\(v)"
    }

    /** Relative time for a draw's next execution: FINISHED / in Xh Ym / date. */
    static func drawRelativeTime(_ ts: Int64?, now: Int64) -> String {
        let diff = ((ts ?? 0) - now) / 1000
        if diff < 0 { return "FINISHED" }
        if diff < 86_400 {
            let h = diff / 3600
            let m = (diff % 3600) / 60
            return h > 0 ? "in \(h)h \(m)m" : "in \(m)m"
        }
        let d = Date(timeIntervalSince1970: Double(ts ?? 0) / 1000)
        let month = format(d, "MMMM").lowercased()
        return "\(format(d, "d")) \(month)/\(format(d, "yyyy"))"
    }

    static func format(_ date: Date, _ pattern: String) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = pattern
        return fmt.string(from: date)
    }

    fileprivate struct DrawRow: View {
        let d: TRaffleDraw
        let now: Int64
        let myAvatar: String?

        var body: some View {
            let dim = d.current_state != RaffleDrawsScreen.STATE_OPEN
            // 🏆 grand / 🔁 recurring marker
            let typeIcon: String? = {
                switch d.execution_type {
                case RaffleDrawTypeExecution.Grand: return "🏆"
                case RaffleDrawTypeExecution.Recurring: return "🔁"
                default: return nil
                }
            }()
            let relative = RaffleDrawsScreen.drawRelativeTime(d.execution_ts, now: now)
            let stateLine: String = {
                if d.current_state == RaffleDrawsScreen.STATE_CANCELLED { return "CANCELLED" }
                if d.current_state == RaffleDrawsScreen.STATE_WINNER_SELECTION { return "Drawing…" }
                if relative == "FINISHED" { return "FINISHED" }
                return "NEXT DRAW: \(relative)"
            }()

            HStack(spacing: 0) {
                ZStack {
                    Color.chromeBorder
                    if let icon = d.icon_url, let u = URL(string: icon) {
                        AsyncImage(url: u) { $0.resizable().scaledToFill() } placeholder: { Color.clear }.allowsHitTesting(false).accessibilityHidden(true)
                    }
                }
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .opacity(dim ? 0.5 : 1)
                Spacer().frame(width: 10)
                VStack(alignment: .leading, spacing: 0) {
                    Text(stripHtml(d.name))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text(stateLine)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.accent)
                    if !stripHtml(d.description).isEmpty {
                        Text(stripHtml(d.description))
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: 0xA9AACB))
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Spacer().frame(width: 6)
                VStack(alignment: .trailing, spacing: 6) {
                    TicketChip(fallbackIcon: "🪐", avatarUrl: nil, value: RaffleDrawsScreen.formatNumber(d.total_tickets_count))
                    TicketChip(fallbackIcon: "🎟️", avatarUrl: myAvatar, value: RaffleDrawsScreen.formatNumber(d.my_tickets_count))
                }
            }
            .padding(10)
            .overlay(alignment: .topLeading) {
                if let typeIcon = typeIcon {
                    Text(typeIcon).font(.system(size: 12)).padding(.leading, 6).padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity)
            // the draw's background art fills the whole row
            .background(
                ZStack {
                    Color.card
                    if let bg = d.background_image_url, !bg.isEmpty,
                       let u = URL(string: d.background_image_url_mobile?.nonEmpty ?? bg) {
                        AsyncImage(url: u) { $0.resizable().scaledToFill() } placeholder: { Color.clear }.allowsHitTesting(false).accessibilityHidden(true)
                            .opacity(dim ? 0.25 : 1)
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    /** Ticket counter chip: the pool (🪐) or the player's own (their avatar). */
    fileprivate struct TicketChip: View {
        let fallbackIcon: String
        let avatarUrl: String?
        let value: String

        var body: some View {
            HStack(spacing: 4) {
                if let avatarUrl = avatarUrl, !avatarUrl.isEmpty, let u = URL(string: avatarUrl) {
                    AsyncImage(url: u) { $0.resizable().scaledToFill() } placeholder: { Color.chromeBorder }.allowsHitTesting(false).accessibilityHidden(true)
                        .frame(width: 18, height: 18)
                        .clipShape(Circle())
                } else {
                    Text(fallbackIcon).font(.system(size: 12))
                }
                Text(value)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color(hex: 0x0F1020, alpha: 0.8))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}
