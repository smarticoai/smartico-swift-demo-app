import SmarticoPublicAPI
import SwiftUI

/**
 * One raffle draw (Raffles.kt `DrawDetailScreen`): ticket pool vs the player's
 * tickets, opt-in when the draw requires it, the prizes with their unlock
 * conditions, and a history sheet of past runs with winners and prize claim.
 */
struct DrawDetailScreen: View {
    let raffleId: Int64
    let drawId: Int64
    let onClose: () -> Void

    @State private var draw: TRaffleDraw?
    @State private var optedIn = false
    @State private var optMsg: String?
    @State private var expanded: [String: Bool] = [:]
    @State private var historyOpen = false

    // history state
    @State private var runs: [TRaffleDrawRun] = []
    @State private var histLoading = true
    @State private var wonByMe = false
    @State private var openRun: Int64?
    @State private var runData: [Int64: TRaffleDraw?] = [:] // nil value = load failed
    @State private var rowMsg: [Int64: String] = [:]

    var body: some View {
        ZStack {
            main
            if historyOpen { historySheet }
        }
        .task(id: "\(raffleId):\(drawId)") { await load() }
    }

    private func load() async {
        draw = (try? await Smartico.api.getRaffles())?
            .first { $0.id == raffleId }?.draws?
            .first { $0.id == drawId }
        optedIn = draw?.user_opted_in == true
        runs = ((try? await Smartico.api.getRaffleDrawRunsHistory(raffle_id: raffleId, draw_id: drawId)) ?? [])
            .sorted { ($0.execution_ts ?? 0) > ($1.execution_ts ?? 0) }
        histLoading = false
        if let d = draw {
            demoLog("draw \(raffleId)/\(drawId): \(stripHtml(d.name)) run_id=\(d.run_id ?? 0) prizes=\(d.prizes?.count ?? 0) total=\(d.total_tickets_count ?? 0) mine=\(d.my_tickets_count ?? 0) requires_optin=\(d.requires_optin == true) opted_in=\(optedIn)")
        } else {
            demoLog("draw \(raffleId)/\(drawId): not found")
        }
        demoLog("draw \(raffleId)/\(drawId) history: \(runs.count) runs, winner=\(runs.filter { $0.is_winner == true }.count), unclaimed=\(runs.filter { $0.has_unclaimed_prize == true }.count)")
    }

    // ------------------------------------------------------------- main ----

    private var main: some View {
        let d = draw
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Text(stripHtml(d?.name).nonEmpty ?? "Draw")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button { historyOpen = true } label: {
                    Text("History" + (histLoading ? "" : " (\(runs.count))"))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.chromeBorder)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                Spacer().frame(width: 10)
                Button(action: onClose) {
                    Text("✕").font(.system(size: 20)).foregroundColor(.muted)
                }
            }
            if let d = d {
                drawBody(d)
            } else {
                Loading()
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func drawBody(_ d: TRaffleDraw) -> some View {
        let total = d.total_tickets_count ?? 0
        let my = d.my_tickets_count ?? 0
        Spacer().frame(height: 8)
        HStack(spacing: 8) {
            Badge(label: "🪐 \(RaffleDrawsScreen.formatNumber(total)) total", tone: .muted)
            Badge(label: "🎟️ \(RaffleDrawsScreen.formatNumber(my)) mine", tone: .accent)
        }

        Spacer().frame(height: 10)
        if d.requires_optin != true {
            Meta("Automatic entry — no opt-in needed")
        } else if optedIn {
            Badge(label: "You're in ✓", tone: .good)
        } else {
            ActionButton(label: "Opt in to this draw", onResult: { optMsg = $0 }) {
                let runId = d.run_id ?? 0
                let r = try await Smartico.api.requestRaffleOptin(
                    raffle_id: raffleId,
                    draw_id: drawId,
                    raffle_run_id: runId
                )
                demoLog("requestRaffleOptin(raffle_id: \(raffleId), draw_id: \(drawId), raffle_run_id: \(runId)) → err_code=\(r.err_code.map { "\($0)" } ?? "nil") err_message=\(r.err_message ?? "nil")")
                if r.err_code == 0 {
                    optedIn = true
                    return "Opted in ✓"
                }
                return r.err_message ?? "Opt-in failed (\(r.err_code.map { "\($0)" } ?? "nil"))"
            }
            if let optMsg = optMsg {
                Spacer().frame(height: 4)
                Meta(optMsg)
            }
        }

        Spacer().frame(height: 12)
        SectionLabel("Prizes (\(d.prizes?.count ?? 0))")
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                let prizes = (d.prizes ?? []).sorted { ($0.priority ?? 0) < ($1.priority ?? 0) }
                if prizes.isEmpty { Meta("No prizes in this draw.") }
                ForEach(Array(prizes.enumerated()), id: \.offset) { _, p in
                    PrizeCard(p: p, total: total, my: my, expanded: $expanded)
                }
                Spacer().frame(height: 24)
            }
        }
    }

    // ---------------------------------------------------- history sheet ----

    private var historySheet: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                Color.black.opacity(0.6)
                    .ignoresSafeArea()
                    .onTapGesture { historyOpen = false }
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 0) {
                        Text(verbatim: "Draw history (\(runs.count))")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button { historyOpen = false } label: {
                            Text("✕").font(.system(size: 20)).foregroundColor(.muted)
                        }
                    }
                    HStack(spacing: 6) {
                        Meta("Won by me")
                        Toggle("", isOn: $wonByMe).labelsHidden().tint(.accent)
                    }
                    let shown = wonByMe ? runs.filter { $0.is_winner == true } : runs
                    if histLoading {
                        Loading()
                    } else if shown.isEmpty {
                        Meta("There are no records available.")
                        Spacer()
                    } else {
                        ScrollView {
                            // lazy: a recurring draw has thousands of past runs (2832 for the hourly one)
                            LazyVStack(spacing: 8) {
                                ForEach(Array(shown.enumerated()), id: \.offset) { _, run in
                                    runRow(run)
                                }
                                Spacer().frame(height: 24)
                            }
                        }
                    }
                }
                .padding(16)
                // the sheet runs on under the home indicator; its content stays above it
                .padding(.bottom, geo.safeAreaInsets.bottom)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .frame(height: geo.size.height * 0.85 + geo.safeAreaInsets.bottom, alignment: .top)
                .background(Color.bg)
                .clipShape(UnevenRoundedCornersB(radius: 20))
            }
            .ignoresSafeArea(edges: .bottom)
        }
    }

    private func runRow(_ run: TRaffleDrawRun) -> some View {
        let runId = run.run_id ?? 0
        return RunRow(
            run: run,
            open: openRun == runId,
            detail: runData[runId] ?? nil,
            loaded: runData.keys.contains(runId),
            message: rowMsg[runId],
            onToggle: {
                openRun = openRun == runId ? nil : runId
                if !runData.keys.contains(runId) {
                    Task {
                        let detail = try? await Smartico.api.getRaffleDrawRun(raffle_id: raffleId, run_id: runId)
                        demoLog("getRaffleDrawRun(raffle_id: \(raffleId), run_id: \(runId)) → \(detail.map { "prizes=\($0.prizes?.count ?? 0) winners=\(($0.prizes ?? []).reduce(0) { $0 + ($1.winners?.count ?? 0) })" } ?? "failed")")
                        // updateValue, not `runData[runId] = detail`: assigning nil would drop the key
                        runData.updateValue(detail, forKey: runId)
                    }
                }
            },
            onClaim: {
                Task {
                    rowMsg[runId] = "Loading…"
                    do {
                        rowMsg[runId] = try await Self.claimRun(raffleId, run)
                    } catch {
                        rowMsg[runId] = "Error: \(error.localizedDescription)"
                    }
                }
            }
        )
    }

    /**
     * Claim flow, as in RN: fetch the full run, find this user's unclaimed prize
     * (a winner row with raf_won_id and no claimed_date) and claim it; otherwise
     * report how many winners the run had.
     */
    private static func claimRun(_ raffleId: Int64, _ run: TRaffleDrawRun) async throws -> String {
        let full = try await Smartico.api.getRaffleDrawRun(raffle_id: raffleId, run_id: run.run_id ?? 0)
        let wonId = (full.prizes ?? [])
            .flatMap { $0.winners ?? [] }
            .first { $0.raf_won_id != nil && $0.claimed_date == nil }?
            .raf_won_id
        if run.has_unclaimed_prize == true, let wonId = wonId {
            let r = try await Smartico.api.claimRafflePrize(won_id: wonId)
            demoLog("claimRafflePrize(won_id: \(wonId)) → errorCode=\(r.errorCode.map { "\($0)" } ?? "nil") errorMessage=\(r.errorMessage ?? "nil")")
            return (r.errorCode ?? 0) == 0 ? "Claimed ✓" : r.errorMessage ?? "Claim failed (\(r.errorCode.map { "\($0)" } ?? "nil"))"
        }
        let n = (full.prizes ?? []).reduce(0) { $0 + ($1.winners?.count ?? 0) }
        return "\(n) winner(s) · nothing to claim"
    }
}

// ---------------------------------------------------------------------------
// Rows. Nested in the screen type so they cannot collide with other files'
// top-level names.
// ---------------------------------------------------------------------------

extension DrawDetailScreen {
    /**
     * One prize: locked until the pool and the player have enough tickets; tapping
     * a locked prize expands the "how to unlock" progress bars.
     */
    fileprivate struct PrizeCard: View {
        let p: TRafflePrize
        let total: Int64
        let my: Int64
        @Binding var expanded: [String: Bool]

        var body: some View {
            let minTotal = p.min_required_total_tickets ?? 0
            let minUser = p.min_required_tickets_for_user ?? 0
            let available = total >= minTotal && my >= minUser
            let canExpand = !available || minTotal > 0 || minUser > 0
            let key = p.id ?? ""
            let open = expanded[key] == true
            let fmt = RaffleDrawsScreen.formatNumber

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    ZStack {
                        Circle().fill(Color.chromeBorder)
                        if let image = p.image_url, let u = URL(string: image) {
                            AsyncImage(url: u) { $0.resizable().scaledToFill() } placeholder: { Color.clear }.allowsHitTesting(false).accessibilityHidden(true)
                                .opacity(available ? 1 : 0.4)
                        }
                        if !available { Text("🔒").font(.system(size: 18)) }
                    }
                    .frame(width: 44, height: 44)
                    .clipShape(Circle())
                    Spacer().frame(width: 12)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(stripHtml(p.name))
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        if available && total > 0 && my > 0 {
                            Text("You have a \(DrawDetailScreen.numbersToRatio(my, total)) chance to win")
                                .font(.system(size: 11))
                                .foregroundColor(.good)
                        } else if !available {
                            Text("Locked — tap for how to unlock")
                                .font(.system(size: 11))
                                .foregroundColor(.muted)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    let mult = Int(p.prizes_per_run_actual ?? 0)
                    if mult > 1 {
                        Text(verbatim: "\(mult)x")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }

                if open {
                    Spacer().frame(height: 10)
                    if minTotal > total {
                        Text("Help gather \(fmt(minTotal - total)) more tickets (all users) to unlock")
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: 0xFF8F8F))
                        UnlockProgress(icon: "🪐", have: total, need: minTotal)
                        Spacer().frame(height: 8)
                    }
                    if minUser > 0 {
                        Text(my >= minUser
                             ? "Your tickets in this draw"
                             : "Collect \(fmt(minUser - my)) more tickets personally to unlock")
                            .font(.system(size: 11))
                            .foregroundColor(my >= minUser ? Color(hex: 0xC9C9E0) : Color(hex: 0xFF8F8F))
                        UnlockProgress(icon: "🎟️", have: my, need: minUser)
                    }
                    if let every = p.add_one_prize_per_each_x_tickets, every > 0 {
                        Spacer().frame(height: 6)
                        Meta("Every \(fmt(every)) extra tickets in the draw adds one more prize.")
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.card)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .contentShape(Rectangle())
            .onTapGesture { if canExpand { expanded[key] = !open } }
            .padding(.bottom, 10)
        }
    }

    fileprivate struct UnlockProgress: View {
        let icon: String
        let have: Int64
        let need: Int64

        var body: some View {
            let pct = need > 0 ? min(Double(have) * 100.0 / Double(need), 100.0) : 100.0
            HStack(spacing: 8) {
                Text(icon).font(.system(size: 14))
                ProgressBar(percent: pct, completed: pct >= 100)
                Text(RaffleDrawsScreen.formatNumber(need))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
            }
            .padding(.top, 4)
        }
    }

    /** One past run: dates, Claim when a prize awaits, expandable winners list. */
    fileprivate struct RunRow: View {
        let run: TRaffleDrawRun
        let open: Bool
        let detail: TRaffleDraw?
        let loaded: Bool
        let message: String?
        let onToggle: () -> Void
        let onClaim: () -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    Button(action: onToggle) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text((run.is_winner == true ? "🏆 " : "") + stripHtml(run.name))
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            // getRaffleDrawRunsHistory fills only execution_ts: without a
                            // ticket window the range line would read "— – Oct 1", so it
                            // is left out and the draw time below says it all
                            if (run.ticket_start_ts ?? 0) > 0 {
                                Meta("\(DrawDetailScreen.monthDay(run.ticket_start_ts)) – \(DrawDetailScreen.monthDay(run.execution_ts))")
                            }
                            Meta(DrawDetailScreen.dateTime(run.execution_ts))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if run.has_unclaimed_prize == true {
                        Button(action: onClaim) {
                            Text("Claim")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Color.accent)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        Spacer().frame(width: 8)
                    }
                    Button(action: onToggle) {
                        Text(open ? "▲ hide" : "▼ winners")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.muted)
                            .padding(.vertical, 8)
                    }
                }
                if let message = message {
                    Spacer().frame(height: 4)
                    Meta(message)
                }
                if open {
                    Spacer().frame(height: 8)
                    if !loaded {
                        Meta("loading…")
                    } else if let detail = detail {
                        let lines = (detail.prizes ?? []).flatMap { p in (p.winners ?? []).map { w in (w, p) } }
                        if lines.isEmpty {
                            Meta("No winners for this run.")
                        } else {
                            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                                WinnerLine(w: line.0, p: line.1)
                            }
                        }
                    } else {
                        Meta("Couldn't load winners.")
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.card)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    fileprivate struct WinnerLine: View {
        let w: TRafflePrizeWinner
        let p: TRafflePrize

        var body: some View {
            HStack(spacing: 0) {
                ZStack {
                    Circle().fill(Color.chromeBorder)
                    if let a = w.avatar_url, let u = URL(string: a) {
                        AsyncImage(url: u) { $0.resizable().scaledToFill() } placeholder: { Color.clear }.allowsHitTesting(false).accessibilityHidden(true)
                    }
                }
                .frame(width: 26, height: 26)
                .clipShape(Circle())
                Spacer().frame(width: 8)
                Text(stripHtml(w.username).nonEmpty ?? "Player")
                    .font(.system(size: 13))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let image = p.image_url, !image.isEmpty, let u = URL(string: image) {
                    AsyncImage(url: u) { $0.resizable().scaledToFit() } placeholder: { Color.clear }
                        .frame(width: 22, height: 22)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    Spacer().frame(width: 6)
                }
                Text(stripHtml(p.name))
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: 0xC9C9E0))
                    .lineLimit(1)
            }
            .padding(.top, 6)
        }
    }

    /** Only the top corners rounded — the sheet sits on the bottom edge. */
    fileprivate struct UnevenRoundedCornersB: Shape {
        let radius: CGFloat

        func path(in rect: CGRect) -> Path {
            let r = min(radius, rect.width / 2, rect.height / 2)
            var p = Path()
            p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
            p.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
            p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + r), control: CGPoint(x: rect.maxX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.closeSubpath()
            return p
        }
    }

    /** "1:Nk" win-chance ratio from the user's tickets vs the pool. */
    static func numbersToRatio(_ mine: Int64, _ total: Int64) -> String {
        if mine <= 0 { return "—" }
        let r = Double(total) / Double(mine)
        func strip(_ x: String) -> String { x.hasSuffix(".0") ? String(x.dropLast(2)) : x }
        if r >= 1_000_000 { return "1:" + strip(String(format: "%.1f", r / 1_000_000)) + "m" }
        if r >= 1_000 { return "1:" + strip(String(format: "%.1f", r / 1_000)) + "k" }
        return "1:\(Int64(r.rounded()))"
    }

    static func monthDay(_ ts: Int64?) -> String {
        guard let ts = ts, ts > 0 else { return "—" }
        return RaffleDrawsScreen.format(Date(timeIntervalSince1970: Double(ts) / 1000), "MMM d")
    }

    static func dateTime(_ ts: Int64?) -> String {
        guard let ts = ts, ts > 0 else { return "—" }
        return RaffleDrawsScreen.format(Date(timeIntervalSince1970: Double(ts) / 1000), "dd/MM/yyyy HH:mm")
    }
}
