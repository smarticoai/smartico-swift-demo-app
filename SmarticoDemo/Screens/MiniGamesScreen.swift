import SmarticoPublicAPI
import SwiftUI

/**
 * Mini-games catalogue (getMiniGames). "Play" opens the game itself in the
 * widget WebView (`Route.widget`), which runs the round — this screen never
 * plays one natively.
 */
struct MiniGamesScreen: View {
    @ObservedObject private var sdk = Sdk.shared

    var body: some View {
        let points = sdk.props["ach_points_balance"]?.double ?? 0
        ApiList(
            title: "Mini-games",
            // MatchX and quizzes are separate experiences, not SAW mini-games —
            // the widget renders them differently, so they stay out of this list.
            load: {
                let all = try await Smartico.api.getMiniGames()
                let games = all.filter { !EXCLUDED_MINIGAMES.contains($0.saw_game_type ?? "") }
                demoLog("mini-games: getMiniGames → \(all.count) templates, \(games.count) listed: " + games.map { "\($0.id ?? 0) \($0.saw_game_type ?? "?")/\($0.saw_buyin_type ?? "?")" }.joined(separator: ", "))
                return games
            }
        ) { g in
            MiniGameCard(game: g, points: points)
        }
    }
}

private struct MiniGameCard: View {
    let game: TMiniGameTemplate
    let points: Double

    var body: some View {
        let g = game
        // Custom mini-games ship their art as promo_image and leave
        // `thumbnail` empty — that's why those cards had no picture. The
        // art is a wide banner, so it goes above the text, not in a square.
        let art = g.promo_image?.nonEmpty ?? g.thumbnail
        Card {
            if let art = art, !art.isEmpty, let u = URL(string: art) {
                Color.bg
                    .frame(maxWidth: .infinity)
                    .frame(height: 110)
                    .overlay(
                        AsyncImage(url: u) { $0.resizable().scaledToFill() } placeholder: { Color.clear }
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .accessibilityLabel(stripHtml(g.name))
                Spacer().frame(height: 10)
            }
            HStack(alignment: .center, spacing: 6) {
                Text(stripHtml(g.name))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                if let type = g.saw_game_type {
                    Badge(label: type, tone: .accent)
                }
            }
            if !stripHtml(g.promo_text).isEmpty { Meta(stripHtml(g.promo_text)) }
            Spacer().frame(height: 8)
            HStack(alignment: .center) {
                Text(miniGameCost(g))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.gold)
                Spacer()
                if canPlayMiniGame(g, points) {
                    ActionButton(label: "Play") {
                        AppRouter.shared.navigate(.widget(dp: miniGameDp(g)))
                        return ""
                    }
                    .accessibilityIdentifier("minigame-play-\(g.id ?? 0)")
                } else {
                    Meta("Not enough balance")
                }
            }
        }
    }
}

/** Separate experiences the demo does not list (RN parity). */
private let EXCLUDED_MINIGAMES: Set<String> = ["matchx", "quiz"]

/** Lootbox templates open their custom section, not the SAW game. */
private let LOOTBOX_MINIGAMES: Set<String> = ["lootbox_weekdays", "lootbox_calendar_days"]

private func miniGameDp(_ g: TMiniGameTemplate) -> String {
    if LOOTBOX_MINIGAMES.contains(g.saw_game_type ?? "") {
        return "dp:gf_section&id=\(g.custom_section_id.map { String($0) } ?? "null")&standalone=true"
    }
    return "dp:gf_saw&id=\(g.id.map { String($0) } ?? "null")&standalone=true"
}

private func miniGameCost(_ g: TMiniGameTemplate) -> String {
    switch g.saw_buyin_type {
    case "points": return "🟡 \(g.buyin_cost_points ?? 0) points"
    case "gems": return "💎 \(Int(g.buyin_cost_gems ?? 0)) gems"
    case "diamonds": return "🔷 \(Int(g.buyin_cost_diamonds ?? 0)) diamonds"
    case "spins": return "🎟️ \(g.spin_count ?? 0) attempts"
    default: return "Free"
    }
}

private func canPlayMiniGame(_ g: TMiniGameTemplate, _ points: Double) -> Bool {
    switch g.saw_buyin_type {
    case "spins": return (g.spin_count ?? 0) > 0
    case "points": return Double(g.buyin_cost_points ?? 0) <= points
    default: return true
    }
}
