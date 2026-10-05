import SmarticoPublicAPI
import SwiftUI
import UIKit

/**
 * The fake slot, ported from the web fake-casino GamePage.
 *
 * There is no reel engine: the "game" is a play-once sprite, and which sprite
 * plays is decided by a tiny state machine so the visuals continue from the
 * previous outcome. The win is DETERMINISTIC — win = bet × multiplier (0 means
 * a loss), so the player literally dials their own outcome. Each spin reports
 * `casino_bet_win` to the demo backend, which settles the wallet.
 */
private enum SlotFsm { case staticFrame, lossToLoss, lossToWin, winToLoss, winToWin }

private extension SlotFsm {
    func sprite(_ game: CasinoGame) -> String {
        switch self {
        case .staticFrame: return game.staticImg
        case .lossToLoss: return game.lossToLoss
        case .lossToWin: return game.lossToWin
        case .winToLoss: return game.winToLoss
        case .winToWin: return game.winToWin
        }
    }

    func next(win: Bool) -> SlotFsm {
        let wasWin = self == .lossToWin || self == .winToWin
        switch (wasWin, win) {
        case (true, true): return .winToWin
        case (true, false): return .winToLoss
        case (false, true): return .lossToWin
        case (false, false): return .lossToLoss
        }
    }
}

struct GameScreen: View {
    let extId: String
    let onClose: () -> Void

    var body: some View {
        if let game = casinoGames.first(where: { $0.extId == extId }) {
            SlotMachine(game: game, onClose: onClose)
        } else {
            ZStack {
                Color.bg.ignoresSafeArea()
                VStack(spacing: 12) {
                    Text("Game not found").foregroundColor(.muted)
                    Button("‹ Back", action: onClose).foregroundColor(.white)
                }
            }
        }
    }
}

private struct SlotMachine: View {
    let game: CasinoGame
    let onClose: () -> Void

    @ObservedObject private var economy = Economy.shared
    @State private var bet = 10
    @State private var mult = 3
    @State private var fsm = SlotFsm.staticFrame
    @State private var spinning = false
    @State private var winShown: Int?
    @State private var spinSeq = 0
    @State private var panelOpen = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // ImageIO hands us the clip's own loop count (once), so each spin's
            // clip plays through and HOLDS its final frame: the reels rest on the
            // outcome and the next transition starts from it — what the state
            // machine is for. (expo-image loops animated files with no stop
            // control and so does Coil, which is why the RN and Kotlin demos cut
            // back to the static frame after the spin window; there is no need to
            // here.) `replayKey` restarts the clip per spin, like Kotlin's
            // key(spinSeq), even when the same transition plays twice in a row.
            AvifImage(url: gameAsset(fsm.sprite(game)), contentMode: .fit, replayKey: spinSeq)
                .accessibilityLabel(game.name)

            VStack(spacing: 0) {
                topBar
                Spacer()
                controls
            }

            if let amount = winShown {
                Text(amount > 0 ? "WIN € \(amount)" : "NO WIN")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundColor(amount > 0 ? .gold : .muted)
                    .shadow(color: .black.opacity(0.7), radius: 6)
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
                    .accessibilityIdentifier("slot-win")
            }

            GeometryReader { geo in
                if !panelOpen {
                    Button { panelOpen = true } label: {
                        Text("🎯")
                            .font(.system(size: 18))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 16)
                            .background(Color.card)
                            .clipShape(SlotHandleShape(radius: 12))
                    }
                    .accessibilityLabel("Related missions")
                    .position(x: geo.size.width - 22, y: geo.size.height / 2)
                } else {
                    // leaves the bet/spin row usable while the panel is open
                    GameSidePanel(extId: game.extId, onClose: { panelOpen = false })
                        .frame(width: geo.size.width * 0.78, height: geo.size.height * 0.72)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }
            }
        }
        .task(id: game.extId) {
            // The four transition clips are ~1MB each. Without this the first spin
            // spends most of its 2s window downloading and the reels only twitch at
            // the end; warming the cache on open makes every spin start at once.
            AvifCache.shared.prefetch([game.lossToLoss, game.lossToWin, game.winToLoss, game.winToWin].map(gameAsset))
        }
    }

    private var topBar: some View {
        HStack {
            Button(action: onClose) {
                Text("‹ Back").foregroundColor(.white)
            }
            Spacer()
            Text(game.name).font(.system(size: 16, weight: .bold)).foregroundColor(.white)
            Spacer()
            Text(String(format: "€ %.2f", economy.balance))
                .foregroundColor(.white)
                .accessibilityIdentifier("slot-balance")
        }
        .padding(14)
    }

    private var controls: some View {
        HStack(alignment: .center) {
            SlotStepper(label: "MULT", value: "×\(mult)", onMinus: { mult = max(mult - 1, 0) }, onPlus: { mult = min(mult + 1, 5) })
            Spacer()
            Button(action: spin) {
                Text(spinning ? "…" : "SPIN")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 88, height: 88)
                    .background(spinning ? Color.muted : Color.accent)
                    .clipShape(Circle())
            }
            .disabled(spinning || bet <= 0)
            .accessibilityLabel("SPIN")
            Spacer()
            SlotStepper(label: "BET", value: "€\(bet)", onMinus: { bet = max(bet - 10, 0) }, onPlus: { bet = min(bet + 10, 500) })
        }
        .padding(16)
    }

    private func spin() {
        spinning = true
        winShown = nil
        let bet = self.bet
        let win = bet * mult
        fsm = fsm.next(win: win > 0)
        spinSeq += 1
        let seq = spinSeq
        let extId = game.extId
        let before = economy.balance
        Task {
            // the backend settles the money; reportSpin reads the wallet back
            do {
                try await Economy.shared.reportSpin(gameExtId: extId, bet: bet, win: win)
                demoLog(String(format: "spin %@ bet=%d win=%d: balance € %.2f → € %.2f", extId, bet, win, before, Economy.shared.balance))
            } catch {
                demoLog("spin report failed: \(error.localizedDescription)")
            }
        }
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { winShown = win }
            spinning = false
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            // a newer spin owns the label now
            if spinSeq == seq { withAnimation(.easeOut(duration: 0.2)) { winShown = nil } }
        }
    }
}

private struct SlotStepper: View {
    let label: String
    let value: String
    let onMinus: () -> Void
    let onPlus: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            Text(label).font(.system(size: 11, weight: .bold)).foregroundColor(.muted)
            HStack(spacing: 8) {
                StepButton(text: "−", label: "\(label) minus", action: onMinus)
                Text(value).font(.system(size: 15, weight: .bold)).foregroundColor(.white).frame(minWidth: 40)
                StepButton(text: "+", label: "\(label) plus", action: onPlus)
            }
        }
    }

    private struct StepButton: View {
        let text: String
        let label: String
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                Text(text)
                    .font(.system(size: 18))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(Color.card)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .accessibilityLabel(label)
        }
    }
}

/** Rounded on the leading side only — the panel handle sits flush with the screen edge (iOS 16 has no UnevenRoundedRectangle). */
private struct SlotHandleShape: Shape {
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        Path(UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: [.topLeft, .bottomLeft],
            cornerRadii: CGSize(width: radius, height: radius)
        ).cgPath)
    }
}

// ------------------------------------------------------------ side panel ----

/**
 * In-game side panel: the missions and tournaments tied to THIS slot, so the
 * player can watch progress while spinning (the web app's GamePageSidebar).
 */
private struct GameSidePanel: View {
    let extId: String
    let onClose: () -> Void

    // Which items belong to this game is fixed per game; the progress inside
    // them is not, so the ids are fetched once and the live numbers come from
    // the store — a spin updates this panel while it stays open.
    @State private var achIds = Set<Int64>()
    @State private var tourIds = Set<Int64>()
    @State private var loaded = false
    @State private var tab = 0
    @State private var note: String?
    @ObservedObject private var store = Store.shared

    var body: some View {
        let missions = store.missions.filter { $0.id.map(achIds.contains) ?? false }
        let tournaments = store.tournaments.filter { $0.tournament_id.map(tourIds.contains) ?? false }
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                SlotPanelTab(label: "🎯 Missions", on: tab == 0) { tab = 0 }
                SlotPanelTab(label: "🏆 Tournaments", on: tab == 1) { tab = 1 }
                Button(action: onClose) {
                    Text("✕").font(.system(size: 17)).foregroundColor(.muted).padding(.horizontal, 4)
                }
                .fixedSize()
                .accessibilityLabel("Close panel")
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if !loaded {
                        Meta("loading…")
                    } else if tab == 0 {
                        if missions.isEmpty {
                            Meta("No missions related to this game.")
                        } else {
                            ForEach(missions.indices, id: \.self) { i in missionCard(missions[i]) }
                            if let note = note { Meta(note) }
                        }
                    } else {
                        if tournaments.isEmpty {
                            Meta("No tournaments related to this game.")
                        } else {
                            ForEach(tournaments.indices, id: \.self) { i in tournamentCard(tournaments[i]) }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(10)
        .background(Color(hex: 0x12132A, alpha: 0.94))
        .task(id: extId) {
            do {
                let related = try await Smartico.api.getRelatedItemsForGame(related_game_id: extId)
                achIds = Set((related.achievements ?? []).compactMap { $0.ach_id })
                tourIds = Set((related.tournaments ?? []).compactMap { $0.tournamentId.map { Int64($0) } })
                demoLog("related items for \(extId): achievements=\(achIds.sorted()) tournaments=\(tourIds.sorted())")
            } catch {
                demoLog("getRelatedItemsForGame(\(extId)) failed: \(error.localizedDescription)")
            }
            Store.shared.refreshTournaments()
            loaded = true
        }
    }

    private func missionCard(_ m: TMissionOrBadge) -> some View {
        let progress = m.progress ?? 0
        return SlotPanelCard {
            HStack(spacing: 8) {
                Thumb(url: m.image, size: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text(stripHtml(m.name))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(2)
                    if let status = slotMissionStatus(m) {
                        Badge(label: status.label, tone: status.tone)
                    }
                }
                Spacer(minLength: 0)
            }
            ProgressBar(percent: progress, completed: m.is_completed == true)
                .padding(.top, 8)
            Text(verbatim: "\(Int(progress))%").font(.system(size: 10)).foregroundColor(.muted)

            ForEach((m.tasks ?? []).indices, id: \.self) { i in
                let t = m.tasks![i]
                let done = t.is_completed == true
                HStack(spacing: 6) {
                    Text(done ? "✔" : "○").font(.system(size: 11)).foregroundColor(done ? .good : .muted)
                    Text(stripHtml(t.name))
                        .font(.system(size: 11))
                        .foregroundColor(done ? .muted : .white)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let exp = t.execution_count_expected {
                        Text(verbatim: "\(Int(t.execution_count_actual ?? 0))/\(Int(exp))")
                            .font(.system(size: 10))
                            .foregroundColor(.muted)
                    }
                    if (t.points_reward ?? 0) > 0 {
                        Text(verbatim: "\(t.points_reward ?? 0)p").font(.system(size: 10)).foregroundColor(.gold)
                    }
                }
                .padding(.top, 4)
            }

            if m.is_requires_optin == true && m.is_opted_in != true && m.is_locked != true {
                ActionButton(label: "Opt-in", onResult: { msg in note = msg; Store.shared.refreshMissions() }) {
                    let r = try await Smartico.api.requestMissionOptIn(missionId: m.id ?? 0)
                    return r.err_code == 0 ? "Opted in ✓" : r.err_message ?? "Failed (\(r.err_code ?? -1))"
                }
                .padding(.top, 6)
            }
        }
    }

    private func tournamentCard(_ t: TTournament) -> some View {
        let prize = stripHtml(t.prize_pool_short)
        return SlotPanelCard {
            Text(stripHtml(t.name))
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.white)
                .lineLimit(2)
            Meta(
                (prize.isEmpty ? "No prize" : prize) +
                    " · \(t.registration_count ?? 0) joined" +
                    (t.is_user_registered == true ? " · you ✓" : "")
            )
            .padding(.top, 4)
        }
    }
}

/** Status pill for a mission (Details.kt `missionStatus`, kept private to the panel). */
private func slotMissionStatus(_ m: TMissionOrBadge) -> (label: String, tone: Color)? {
    if m.is_locked == true { return ("Locked", .muted) }
    if m.is_completed == true { return ("Completed", .good) }
    if m.is_opted_in == true { return ("In Progress", .accent) }
    if m.is_requires_optin == true { return ("Opt-in", .accent) }
    return nil
}

private struct SlotPanelTab: View {
    let label: String
    let on: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(on ? .white : .muted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(on ? Color.accent : Color.card)
                .clipShape(RoundedRectangle(cornerRadius: 9))
        }
    }
}

private struct SlotPanelCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.card)
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
