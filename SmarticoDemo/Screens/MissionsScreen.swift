import SmarticoPublicAPI
import SwiftUI

/**
 * Missions tab — Screens.kt `MissionsScreen` + `MissionCard`, with the badges
 * grid (ProfileExtras.kt `BadgesSection`) as its second section.
 *
 * The store owns the list: server pushes refresh it, so progress moves while
 * this screen is open and the visible list is never dropped for a spinner
 * mid-refresh.
 *
 * Kotlin expands a card in place; here a tap opens the same content as a
 * detail sheet (tasks, related games, unlock hint, live timer), and the sheet
 * reads the mission from the store by id, so an opt-in or a push updates it
 * while it is open.
 */
struct MissionsScreen: View {
    @ObservedObject private var store = Store.shared
    @State private var section: MissionsSection = .missions
    @State private var detail: MissionRef?
    /** The last action result per mission, shared by the card and the detail sheet. */
    @State private var notes: [Int64: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Missions")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.white)
                .padding(.vertical, 12)

            HStack(spacing: 8) {
                SegmentTab(label: "🎯 Missions (\(store.missions.count))", on: section == .missions) { section = .missions }
                SegmentTab(
                    label: "🏅 Badges (\(store.badges.filter { $0.is_completed == true }.count)/\(store.badges.count))",
                    on: section == .badges
                ) { section = .badges }
            }
            .padding(.bottom, 12)

            switch section {
            case .missions:
                missionsList
            case .badges:
                ScrollView {
                    if store.badges.isEmpty {
                        Text(store.loaded ? "Nothing here yet." : "Loading badges…").foregroundColor(.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        BadgesSection()
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            Store.shared.refreshMissions()
            Store.shared.refreshBadges()
        }
        .onChange(of: store.missions) { logSummary($0) }
        .onAppear { logSummary(store.missions) }
        .sheet(item: $detail) { ref in
            MissionDetailSheet(missionId: ref.id, note: noteBinding(ref.id)) { detail = nil }
        }
    }

    @ViewBuilder
    private var missionsList: some View {
        let missions = store.missions
        if missions.isEmpty && !store.loaded {
            Loading()
        } else if missions.isEmpty {
            Text("Nothing here yet.").foregroundColor(.muted)
            Spacer()
        } else {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(missions, id: \.id) { m in
                        MissionCard(m: m, note: noteBinding(m.id ?? 0)) {
                            demoLog("mission detail → \(m.id ?? 0) \(stripHtml(m.name))")
                            detail = MissionRef(id: m.id ?? 0)
                        }
                    }
                }
                .padding(.bottom, 24)
            }
        }
    }

    /** One line per refresh: what the list holds and which actions are live — the screen's log evidence. */
    private func logSummary(_ missions: [TMissionOrBadge]) {
        if missions.isEmpty { return }
        func ids(_ f: (TMissionOrBadge) -> Bool) -> String {
            let hit = missions.filter(f).map { "\($0.id ?? 0)" }
            return hit.isEmpty ? "-" : hit.joined(separator: ",")
        }
        demoLog(
            "missions screen: \(missions.count) missions" +
                " · locked=\(missions.filter { $0.is_locked == true }.count)" +
                " · completed=\(missions.filter { $0.is_completed == true }.count)" +
                " · opt-in=[\(ids { $0.is_requires_optin == true && $0.is_opted_in != true && $0.is_locked != true })]" +
                " · opted-in=[\(ids { $0.is_opted_in == true })]" +
                " · claimable=[\(ids { $0.is_completed == true && $0.requires_prize_claim == true && $0.prize_claimed_date_ts == nil && $0.ach_completed_id != nil })]" +
                " · cta=[\(ids { $0.cta_action != nil && $0.cta_text != nil })]" +
                " · ribbons=[\(missions.compactMap { m in ribbonText(m).map { "\(m.id ?? 0):\($0)" } }.joined(separator: ","))]" +
                " · availability=[\(Dictionary(grouping: missions) { $0.availability_status ?? -1 }.map { "\($0.key):\($0.value.count)" }.sorted().joined(separator: ","))]" +
                " · badges=\(store.badges.count)"
        )
    }

    private func noteBinding(_ id: Int64) -> Binding<String?> {
        Binding(get: { notes[id] }, set: { notes[id] = $0 })
    }
}

private enum MissionsSection { case missions, badges }

/** `.sheet(item:)` wants an Identifiable; the mission itself is looked up live. */
private struct MissionRef: Identifiable {
    let id: Int64
}

private struct SegmentTab: View {
    let label: String
    let on: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(on ? .white : .muted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(on ? Color.accent : Color.card)
                .clipShape(RoundedRectangle(cornerRadius: 9))
        }
    }
}

// ----------------------------------------------------------------- card ----

/**
 * One mission. Collapsed it shows identity + progress and the actions; tapping
 * opens the detail sheet with the tasks, related games, unlock hint and live
 * timer — the same content the RN demo expands in place.
 */
private struct MissionCard: View {
    let m: TMissionOrBadge
    @Binding var note: String?
    let onOpen: () -> Void

    var body: some View {
        let completed = m.is_completed == true
        let progress = m.progress ?? 0
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top, spacing: 12) {
                        MissionImage(url: m.image, ribbon: ribbonText(m), size: 56)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(stripHtml(m.name))
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                if let st = missionStatus(m) {
                                    Badge(label: st.label, tone: st.tone)
                                }
                            }
                            if !stripHtml(m.sub_header).isEmpty { Meta(stripHtml(m.sub_header)) }
                            if !stripHtml(m.description).isEmpty {
                                Text(stripHtml(m.description))
                                    .font(.system(size: 12))
                                    .foregroundColor(.muted)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                            }
                            if !stripHtml(m.reward).isEmpty {
                                Text("Reward: \(stripHtml(m.reward))")
                                    .font(.system(size: 12))
                                    .foregroundColor(.gold)
                                    .multilineTextAlignment(.leading)
                            }
                        }
                        Spacer(minLength: 0)
                        Text("›").font(.system(size: 18, weight: .bold)).foregroundColor(.muted)
                    }

                    // always drawn, including at 0% — an empty bar still tells the
                    // player this mission is measured
                    HStack {
                        Meta("Progress")
                        Spacer()
                        Text("\(Int(progress))%")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .padding(.top, 10)
                    ProgressBar(percent: progress, completed: completed)
                        .padding(.top, 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("mission-\(m.id ?? 0)")

            MissionActions(m: m, note: $note)
            if let note = note, !note.isEmpty {
                Meta(note).padding(.top, 6)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

/** Mission artwork with the operator's ribbon ("hot", "new", custom text) pinned on top. */
private struct MissionImage: View {
    let url: String?
    let ribbon: String?
    let size: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 10).fill(Color.bg)
            Thumb(url: url, size: size)
            if let ribbon = ribbon {
                Text(ribbon.uppercased())
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundColor(.bg)
                    .lineLimit(1)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color.gold)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
        .frame(width: size, height: size)
    }
}

// -------------------------------------------------------------- actions ----

/**
 * Opt-in / CTA / claim — the same rules as the Kotlin card: opt-in wins over the
 * CTA (a mission you have not joined cannot be played towards), and the claim
 * button only shows for a completed mission whose prize is still unclaimed.
 */
private struct MissionActions: View {
    let m: TMissionOrBadge
    @Binding var note: String?
    /** "card" or "detail" — keeps the UI-test identifiers of the two copies apart. */
    var context = "card"
    /** Runs before a CTA deep link — the detail sheet closes itself so the target screen is visible. */
    var beforeCta: (() -> Void)? = nil

    var body: some View {
        let locked = m.is_locked == true
        let completed = m.is_completed == true
        let canOptin = m.is_requires_optin == true && m.is_opted_in != true && !locked
        let canClaim = completed && m.requires_prize_claim == true &&
            m.prize_claimed_date_ts == nil && m.ach_completed_id != nil
        let cta = ctaOf(m)
        if canOptin || canClaim || cta != nil {
            HStack(spacing: 8) {
                if canOptin {
                    ActionButton(label: "Opt-in", onResult: { note = $0; Store.shared.refreshMissions() }) {
                        try await missionOptIn(m)
                    }
                    .accessibilityIdentifier("\(context)-optin-\(m.id ?? 0)")
                } else if let cta = cta {
                    // Campaign CTAs are deep links ("dp:gf_saw&id=…", operator
                    // URLs…): the SDK router sends them to the right screen.
                    PillButton(label: stripHtml(cta.text)) {
                        demoLog("mission \(m.id ?? 0) CTA → \(cta.action)")
                        if let beforeCta = beforeCta {
                            beforeCta()
                            // let the sheet finish dismissing before the router pushes a screen
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { Smartico.dp(cta.action) }
                        } else {
                            Smartico.dp(cta.action)
                        }
                    }
                    .accessibilityIdentifier("\(context)-cta-\(m.id ?? 0)")
                }
                if canClaim {
                    ActionButton(label: m.claim_button_title ?? "Claim reward", onResult: { note = $0; Store.shared.refreshMissions() }) {
                        try await missionClaim(m)
                    }
                    .accessibilityIdentifier("\(context)-claim-\(m.id ?? 0)")
                }
            }
            .padding(.top, 10)
        }
    }
}

/** A mission's CTA, only when both halves are there (Kotlin: `cta_action != null && cta_text != null`). */
private func ctaOf(_ m: TMissionOrBadge) -> (action: String, text: String)? {
    guard let action = m.cta_action, let text = m.cta_text else { return nil }
    return (action, text)
}

/** Join a mission. The reply is logged: it is the live check of the request keys. */
@MainActor
private func missionOptIn(_ m: TMissionOrBadge) async throws -> String {
    let id = m.id ?? 0
    demoLog("requestMissionOptIn(missionId: \(id)) → sending")
    do {
        let r = try await Smartico.api.requestMissionOptIn(missionId: id)
        demoLog("requestMissionOptIn(missionId: \(id)) ← err_code=\(r.err_code.map { String($0) } ?? "nil") err_message=\(r.err_message ?? "nil")")
        return r.err_code == 0 ? "Opted in ✓" : r.err_message ?? "Failed (\(r.err_code.map { String($0) } ?? "null"))"
    } catch {
        demoLog("requestMissionOptIn(missionId: \(id)) failed: \(error)")
        throw error
    }
}

/** Claim the prize of the completion `ach_completed_id` names. */
@MainActor
private func missionClaim(_ m: TMissionOrBadge) async throws -> String {
    let id = m.id ?? 0
    let completedId = m.ach_completed_id ?? 0
    demoLog("requestMissionClaimReward(missionId: \(id), achCompletedId: \(completedId)) → sending")
    do {
        let r = try await Smartico.api.requestMissionClaimReward(missionId: id, achCompletedId: completedId)
        demoLog("requestMissionClaimReward(missionId: \(id)) ← err_code=\(r.err_code.map { String($0) } ?? "nil") err_message=\(r.err_message ?? "nil")")
        return r.err_code == 0 ? "Claimed ✓" : r.err_message ?? "Failed (\(r.err_code.map { String($0) } ?? "null"))"
    } catch {
        demoLog("requestMissionClaimReward(missionId: \(id)) failed: \(error)")
        throw error
    }
}

/** ActionButton's look for a plain synchronous action (deep links must run on the main thread). */
private struct PillButton: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.accent)
                .clipShape(Capsule())
        }
    }
}

// --------------------------------------------------------------- detail ----

/** The expanded mission (Kotlin's `if (open) { … }` block) as a sheet. */
private struct MissionDetailSheet: View {
    let missionId: Int64
    @Binding var note: String?
    let onClose: () -> Void

    @ObservedObject private var store = Store.shared
    // ticks only while this sheet is open
    @StateObject private var clock = NowTicker()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Mission").font(.system(size: 17, weight: .bold)).foregroundColor(.white)
                Spacer()
                Button(action: onClose) {
                    Text("✕").font(.system(size: 20)).foregroundColor(.muted)
                }
                .accessibilityIdentifier("mission-detail-close")
            }
            .padding(16)

            if let m = store.missions.first(where: { $0.id == missionId }) {
                ScrollView {
                    content(m, now: clock.now)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 32)
                }
            } else {
                Meta("This mission is no longer available.").padding(16)
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.bg.ignoresSafeArea())
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private func content(_ m: TMissionOrBadge, now: Int64) -> some View {
        let locked = m.is_locked == true
        let completed = m.is_completed == true
        let progress = m.progress ?? 0
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                MissionImage(url: m.image, ribbon: ribbonText(m), size: 88)
                VStack(alignment: .leading, spacing: 4) {
                    Text(stripHtml(m.name))
                        .font(.system(size: 19, weight: .bold))
                        .foregroundColor(.white)
                    if let st = missionStatus(m) { Badge(label: st.label, tone: st.tone) }
                    if !stripHtml(m.sub_header).isEmpty { Meta(stripHtml(m.sub_header)) }
                }
                Spacer(minLength: 0)
            }

            if !stripHtml(m.description).isEmpty {
                Text(stripHtml(m.description))
                    .font(.system(size: 13))
                    .foregroundColor(.muted)
                    .padding(.top, 12)
            }
            if !stripHtml(m.reward).isEmpty {
                Text("Reward: \(stripHtml(m.reward))")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.gold)
                    .padding(.top, 8)
            }

            HStack {
                Meta("Progress")
                Spacer()
                Text("\(Int(progress))%").font(.system(size: 12, weight: .bold)).foregroundColor(.white)
            }
            .padding(.top, 14)
            ProgressBar(percent: progress, completed: completed).padding(.top, 4)

            // when the mission can be played: window, time limit, recurrence
            ForEach(availabilityNotes(m, now: now), id: \.self) { line in
                Meta(line).padding(.top, 6)
            }

            let tasks = m.tasks ?? []
            if !tasks.isEmpty {
                SectionLabel("Tasks").padding(.top, 16)
                ForEach(Array(tasks.enumerated()), id: \.offset) { _, t in
                    TaskRow(t: t)
                }
            }

            let games = (m.related_games ?? []).compactMap { $0.game_public_meta?["image"]?.string }
            if !games.isEmpty {
                SectionLabel("Related games").padding(.top, 14)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(games, id: \.self) { img in
                            Thumb(url: img, size: 52)
                                .background(Color.card)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }

            if locked && !stripHtml(m.unlock_mission_description).isEmpty {
                SectionLabel("How do I unlock this?").padding(.top, 14)
                Meta(stripHtml(m.unlock_mission_description))
            }

            let limit = m.time_limit_ms ?? 0
            if limit > 0, let start = m.dt_start, let left = countdown(start + limit, now: now) {
                Meta("Mission duration: \(left)").padding(.top, 8)
            }

            MissionActions(m: m, note: $note, context: "detail", beforeCta: onClose)
            if let note = note, !note.isEmpty {
                Meta(note).padding(.top, 6)
            }
        }
    }
}

private struct TaskRow: View {
    let t: TMissionOrBadgeTask

    var body: some View {
        let done = t.is_completed == true
        HStack(spacing: 8) {
            // U+FE0E keeps ✔ a text glyph — iOS would otherwise draw the grey emoji and ignore the colour
            Text(done ? "✔\u{FE0E}" : "○").font(.system(size: 13)).foregroundColor(done ? .good : .muted)
            Text(stripHtml(t.name))
                .font(.system(size: 12))
                .foregroundColor(done ? .muted : .white)
                .lineLimit(1)
            Spacer(minLength: 0)
            if let expected = t.execution_count_expected {
                Meta("\(Int(t.execution_count_actual ?? 0))/\(Int(expected))")
            }
            if (t.points_reward ?? 0) > 0 {
                Text("\(t.points_reward ?? 0) pts").font(.system(size: 11)).foregroundColor(.gold)
            }
        }
        .padding(.vertical, 3)
    }
}

// -------------------------------------------------------- derived state ----

/** Status pill shared by the missions list and the detail (Details.kt `missionStatus`). */
private func missionStatus(_ m: TMissionOrBadge) -> (label: String, tone: Color)? {
    if m.is_locked == true { return ("Locked", .muted) }
    if m.is_completed == true { return ("Completed", .good) }
    if m.is_opted_in == true { return ("In Progress", .accent) }
    if m.is_requires_optin == true { return ("Opt-in", .accent) }
    return nil
}

/** The ribbon the SDK resolved from `label_tag` ("custom" already replaced by the operator's text). */
private func ribbonText(_ m: TMissionOrBadge) -> String? {
    guard let text = m.ribbon?.string?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
    return text
}

/**
 * Human lines for the SDK's availability state machine (`availability_status`)
 * plus recurrence. The time-limit countdown itself is Kotlin's "Mission
 * duration" line, so the limited states only explain what is not on screen.
 */
private func availabilityNotes(_ m: TMissionOrBadge, now: Int64) -> [String] {
    typealias S = AchievementAvailabilityStatus
    var lines: [String] = []
    switch m.availability_status ?? -1 {
    case S.UnavailableWithActiveFrom:
        if let from = m.active_from_ts, let left = countdown(from, now: now) {
            lines.append("⏳ Starts in \(left)")
        } else {
            lines.append("⏳ Not started yet")
        }
    case S.AvailableWithActiveTill, S.AvailableWithActiveTillInactive, S.AvailableWithActiveTillActive,
         S.AvailableFullyLimited, S.AvailableFullyLimitedInactive, S.AvailableFullyLimitedActive:
        if let till = m.active_till_ts, let left = countdown(till, now: now) {
            lines.append("⏱ Ends in \(left)")
        }
    case S.MissedByActiveTill:
        lines.append("✕ Missed — the mission has ended")
    case S.MissedByLimitInTime:
        lines.append("✕ Missed — the time limit ran out")
    default:
        break
    }
    let limit = m.time_limit_ms ?? 0
    if limit > 0 && (m.availability_status == S.AvailableLimitedInactive || m.availability_status == S.AvailableFullyLimitedInactive) {
        lines.append("⏱ \(durationText(limit)) to complete once started")
    }
    if let next = m.next_recurrence_date_ts, let left = countdown(next, now: now) {
        lines.append("🔁 Available again in \(left)")
    }
    if let max = m.max_completion_count, max > 0 {
        lines.append("🔁 Completed \(m.completion_count ?? 0)/\(max) times")
    }
    return lines
}

/** "2d 4h" / "3h 20m" / "45m" for a time limit in milliseconds. */
private func durationText(_ ms: Int64) -> String {
    let m = ms / 60_000
    let d = m / 1440
    let h = (m % 1440) / 60
    if d > 0 { return "\(d)d \(h)h" }
    if h > 0 { return "\(h)h \(m % 60)m" }
    return "\(m)m"
}

// --------------------------------------------------------------- badges ----

/**
 * Badges grid with a detail sheet, ported from the RN profile: unearned badges
 * render dimmed, and the operator's excluded custom section (1128) is hidden
 * (the store already filters it). Shown on the Missions tab and on Profile.
 */
struct BadgesSection: View {
    @ObservedObject private var store = Store.shared
    @State private var selected: BadgeRef?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 5)

    var body: some View {
        let badges = store.badges
        Group {
            if !badges.isEmpty {
                Card {
                    Title("Badges (\(badges.filter { $0.is_completed == true }.count)/\(badges.count))")
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(badges, id: \.id) { b in
                            Button {
                                selected = BadgeRef(id: b.id ?? 0)
                            } label: {
                                Thumb(url: b.image, size: 52)
                                    .frame(width: 52, height: 52)
                                    .background(Color.bg)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .opacity(b.is_completed == true ? 1 : 0.28)
                            }
                            .accessibilityLabel(stripHtml(b.name))
                            .accessibilityIdentifier("badge-\(b.id ?? 0)")
                        }
                    }
                    .padding(.top, 10)
                }
            }
        }
        .task { Store.shared.refreshBadges() }
        .sheet(item: $selected) { ref in
            BadgeDetailSheet(badge: store.badges.first { $0.id == ref.id }) { selected = nil }
        }
    }
}

private struct BadgeRef: Identifiable {
    let id: Int64
}

private struct BadgeDetailSheet: View {
    let badge: TMissionOrBadge?
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let b = badge {
                let earned = b.is_completed == true
                Text(stripHtml(b.name)).font(.system(size: 19, weight: .bold)).foregroundColor(.white)
                Thumb(url: b.image, size: 96)
                    .opacity(earned ? 1 : 0.35)
                    .padding(.top, 12)
                if !stripHtml(b.description).isEmpty {
                    Text(stripHtml(b.description)).font(.system(size: 13)).foregroundColor(.muted).padding(.top, 8)
                }
                if let state = badgeTimeState(b) {
                    Meta(state).padding(.top, 6)
                }
                Text(earned ? "✓ Earned" : "Not earned yet")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(earned ? .good : .muted)
                    .padding(.top, 8)
            }
            Spacer(minLength: 12)
            HStack {
                Spacer()
                Button(action: onClose) {
                    Text("Close").font(.system(size: 15, weight: .semibold)).foregroundColor(.accent)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.card.ignoresSafeArea())
        .presentationDetents([.medium])
    }
}

/** The SDK's client-side `badgeTimeLimitState`, for time-boxed badges only. */
private func badgeTimeState(_ b: TMissionOrBadge) -> String? {
    typealias S = BadgesTimeLimitStates
    let now = nowMillis()
    switch b.badgeTimeLimitState ?? -1 {
    case S.BeforeStartDate:
        return b.active_from_ts.flatMap { countdown($0, now: now) }.map { "⏳ Starts in \($0)" } ?? "⏳ Not started yet"
    case S.AfterStartDateNoProgressAndEndDate, S.AfterStartDateWithProgressAndEndDate:
        return b.active_till_ts.flatMap { countdown($0, now: now) }.map { "⏱ Ends in \($0)" }
    case S.AfterEndDateNotStarted, S.AfterEndDateWithProgress:
        return "✕ Expired"
    default:
        return nil
    }
}
