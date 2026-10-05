import SmarticoPublicAPI
import SwiftUI

/**
 * Profile tab (Screens.kt `ProfileScreen`): identity with the name editor and
 * the avatar picker link, balances from the public props, shortcuts, the
 * badges grid, and — beyond the Kotlin screen — the points activity log and
 * the account actions (reset progress, log out) the burger menu also offers.
 */
struct ProfileScreen: View {
    @ObservedObject private var sdk = Sdk.shared
    @State private var editName = false
    @State private var confirmReset = false
    @State private var accountNote: String?

    var body: some View {
        let router = AppRouter.shared
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Profile")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)

                Card {
                    HStack(spacing: 12) {
                        Button { router.navigate(.avatar) } label: {
                            AvatarCircle(url: sdk.avatarUrl(), size: 56)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Title(sdk.displayName())
                                Button { editName = true } label: {
                                    Text("  ✎").font(.system(size: 15)).foregroundColor(.accent)
                                }
                                .accessibilityIdentifier("profile-edit-name")
                            }
                            Meta(sdk.identified ? "ICE · connected ✓" : "connecting…")
                            Meta(sdk.extUserId)
                            Button { router.navigate(.avatar) } label: {
                                Text("Change avatar ›").font(.system(size: 12)).foregroundColor(.accent)
                            }
                            .accessibilityIdentifier("profile-change-avatar")
                        }
                        Spacer(minLength: 0)
                    }
                }

                Card {
                    Title("Balances")
                    VStack(alignment: .leading, spacing: 2) {
                        Meta("🟡 Points: \(sdk.prop("ach_points_balance") ?? "—")   ⭐ \(sdk.prop("ach_level_current") ?? "—")")
                        Meta("💎 Gems: \(sdk.prop("ach_gems_balance") ?? "—")   🔷 Diamonds: \(sdk.prop("ach_diamonds_balance") ?? "—")")
                        Meta("✉️ Unread inbox: \(sdk.prop("core_inbox_unread_count") ?? "—")  ·  props: \(sdk.props.count)")
                    }
                    .padding(.top, 6)
                }

                Card {
                    Title("More")
                    HStack(spacing: 8) {
                        LinkPill(label: "VIP") { router.navigate(.vip) }
                        LinkPill(label: "Levels") { router.navigate(.levels) }
                        LinkPill(label: "Leaderboard") { router.navigate(.leaderboard) }
                    }
                    .padding(.top, 8)
                    HStack(spacing: 8) {
                        LinkPill(label: "Store") { router.navigate(.store) }
                        LinkPill(label: "Jackpots") { router.navigate(.jackpots) }
                        LinkPill(label: "Raffles") { router.navigate(.raffles) }
                    }
                    .padding(.top, 8)
                }

                BadgesSection()

                ActivitySection(userKey: "\(sdk.extUserId)|\(sdk.identified)")

                Card {
                    Title("Account")
                    HStack(spacing: 8) {
                        LinkPill(label: "♻️ Reset progress", tone: .chromeBorder) { confirmReset = true }
                        LinkPill(label: "Log out", tone: .danger) {
                            demoLog("profile → log out")
                            Sdk.shared.logout()
                        }
                    }
                    .padding(.top, 8)
                    if let note = accountNote { Meta(note).padding(.top, 6) }
                }
            }
            .padding(16)
        }
        .sheet(isPresented: $editName) {
            NameDialog(onDismiss: { editName = false })
        }
        .confirmationDialog(
            "Start over as a fresh player? Points, levels and missions will reset.",
            isPresented: $confirmReset,
            titleVisibility: .visible
        ) {
            Button("Reset", role: .destructive) {
                Task {
                    // The backend clones the player under a fresh ext id and
                    // the SDK re-identifies as that user (Sdk.resetProgress).
                    accountNote = "Resetting…"
                    accountNote = await Sdk.shared.resetProgress()
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

/** Round avatar with a placeholder while (or when) there is no image. */
private struct AvatarCircle: View {
    let url: String?
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(Color.chromeBorder)
            if let url = url, let u = URL(string: url) {
                AsyncImage(url: u) { $0.resizable().scaledToFill() } placeholder: {
                    Text("👤").font(.system(size: size * 0.45))
                }
            } else {
                Text("👤").font(.system(size: size * 0.45))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

/** A navigation shortcut in ActionButton's look (navigation is synchronous, so no busy state). */
private struct LinkPill: View {
    let label: String
    var tone: Color = .accent
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(tone)
                .clipShape(Capsule())
        }
    }
}

// ------------------------------------------------------------- activity ----

/**
 * The points / gems / diamonds history (getActivityLog) for the last 30 days,
 * newest first. One page of 20 is plenty for a profile card; the server caps a
 * page at 50 anyway. Reloads when the player changes (reset progress, login).
 */
private struct ActivitySection: View {
    let userKey: String

    @State private var rows: [TActivityLog]?
    @State private var failure: String?

    var body: some View {
        Card {
            Title("Activity")
            Meta("Points, gems and diamonds — last 30 days")
            VStack(alignment: .leading, spacing: 0) {
                if let failure = failure {
                    Text("Error: \(failure)").font(.system(size: 12)).foregroundColor(.danger)
                } else if let rows = rows {
                    if rows.isEmpty {
                        Meta("No activity yet.")
                    } else {
                        let amounts = displayAmounts(rows)
                        ForEach(Array(rows.enumerated()), id: \.offset) { i, r in
                            if i > 0 { Divider().background(Color.chromeBorder) }
                            ActivityRow(r: r, amount: amounts[i])
                        }
                    }
                } else {
                    Meta("Loading…")
                }
            }
            .padding(.top, 8)
        }
        .task(id: userKey) {
            guard userKey.hasSuffix("|true") else { return } // wait for identify
            let now = Int64(Date().timeIntervalSince1970)
            do {
                let list = try await Smartico.api.getActivityLog(
                    startTimeSeconds: now - 30 * 24 * 3600,
                    endTimeSeconds: now,
                    from: 0,
                    to: 20
                )
                rows = list.sorted { ($0.create_date ?? 0) > ($1.create_date ?? 0) }
                failure = nil
                let sorted = rows ?? []
                let amounts = displayAmounts(sorted)
                demoLog("activity log: \(list.count) entries, \(list.filter { $0.amount == nil }.count) without `amount`" + (sorted.first.map { ", newest: type=\($0.type ?? -1) source_type_id=\($0.source_type_id ?? -1) balance=\($0.balance.map(formatAmount) ?? "nil") delta=\(amounts.first.flatMap { $0 }.map(formatAmount) ?? "nil")" } ?? ""))
            } catch {
                failure = error.localizedDescription
                demoLog("activity log failed: \(error)")
            }
        }
    }
}

private struct ActivityRow: View {
    let r: TActivityLog
    let amount: Double?

    var body: some View {
        HStack(spacing: 10) {
            Text(balanceIcon(r.type)).font(.system(size: 16))
            VStack(alignment: .leading, spacing: 1) {
                Text(activityTitle(r))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Meta(activityDate(r.create_date) + (r.balance.map { " · balance \(formatAmount($0))" } ?? ""))
            }
            Spacer(minLength: 4)
            Text(amount.map { ($0 > 0 ? "+" : "") + formatAmount($0) } ?? "—")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(amount == nil ? .muted : (amount ?? 0) >= 0 ? .good : .danger)
        }
        .padding(.vertical, 6)
    }
}

/**
 * The delta per row. Gems/diamonds rows carry `amount`; POINTS rows arrive with
 * the delta in `points_collected`, which TActivityLog does not expose (the SDK
 * maps only `amount` — the JS SDK reads `amount ?? points_collected`). Until the
 * SDK maps it, a points row's delta is recovered from its balance and the
 * balance of the next older points row; the oldest row on the page shows "—".
 */
private func displayAmounts(_ rows: [TActivityLog]) -> [Double?] {
    rows.indices.map { i in
        let r = rows[i]
        if let amount = r.amount { return amount }
        guard r.type == UserBalanceType.Points, let balance = r.balance else { return nil }
        let older = rows[(i + 1)...].first { $0.type == UserBalanceType.Points && $0.balance != nil }
        return older?.balance.map { balance - $0 }
    }
}

/** `type` is the balance the entry moved (UserBalanceType). */
private func balanceIcon(_ type: Int64?) -> String {
    switch type ?? -1 {
    case UserBalanceType.Gems: return "💎"
    case UserBalanceType.Diamonds: return "🔷"
    default: return "🟡"
    }
}

/** What caused the change: the entity's name when the server sends one, else the source type. */
private func activityTitle(_ r: TActivityLog) -> String {
    if let name = r.meta?.name ?? r.source_entity_name, !stripHtml(name).isEmpty { return stripHtml(name) }
    switch r.source_type_id ?? -1 {
    case PointChangeSourceType.Journey: return "Campaign"
    case PointChangeSourceType.AchievementTaskCompletion: return "Mission task completed"
    case PointChangeSourceType.AchievementCompletion: return "Mission completed"
    case PointChangeSourceType.LevelsStructureChange: return "Levels change"
    case PointChangeSourceType.StorePurchase: return "Store purchase"
    case PointChangeSourceType.ManualAdjustment: return "Manual adjustment"
    case PointChangeSourceType.Leaderboard: return "Leaderboard"
    case PointChangeSourceType.Tournament: return "Tournament"
    case PointChangeSourceType.AutomationRule: return "Automation rule"
    case PointChangeSourceType.TournamentRegistration: return "Tournament registration"
    case PointChangeSourceType.TournamentRegistrationCancellation: return "Tournament registration cancelled"
    case PointChangeSourceType.RefundPoints: return "Refund"
    case PointChangeSourceType.PlayMiniGame: return "Mini-game play"
    case PointChangeSourceType.WinMiniGame: return "Mini-game win"
    case PointChangeSourceType.API: return "API"
    case PointChangeSourceType.DynamicFormula: return "Dynamic formula"
    case PointChangeSourceType.Jackpot: return "Jackpot"
    case PointChangeSourceType.Raffle: return "Raffle"
    case PointChangeSourceType.Avatars: return "Avatar"
    case PointChangeSourceType.Clan: return "Clan"
    default: return "Balance change"
    }
}

/** `create_date` is epoch SECONDS on this endpoint. */
private func activityDate(_ seconds: Int64?) -> String {
    guard let seconds = seconds, seconds > 0 else { return "—" }
    let fmt = DateFormatter()
    fmt.locale = Locale(identifier: "en_US_POSIX")
    fmt.dateFormat = "MMM d, HH:mm"
    return fmt.string(from: Date(timeIntervalSince1970: Double(seconds)))
}

private func formatAmount(_ v: Double) -> String {
    v == v.rounded() ? String(Int64(v)) : String(format: "%.2f", v)
}
