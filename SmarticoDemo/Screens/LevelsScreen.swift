import SmarticoPublicAPI
import SwiftUI

/**
 * The level ladder (Screens.kt `LevelsScreen`), cheapest first. The row the
 * player is on is outlined, from `ach_level_current_id` in the public props —
 * the same id `getCurrentLevel` resolves against.
 */
struct LevelsScreen: View {
    @ObservedObject private var sdk = Sdk.shared

    var body: some View {
        let currentId = sdk.props["ach_level_current_id"]?.int64
        ApiList(title: "Levels", load: {
            let levels = try await Smartico.api.getLevels().sorted { ($0.required_points ?? 0) < ($1.required_points ?? 0) }
            demoLog("levels loaded: \(levels.count)")
            return levels
        }) { (l: TLevel) in
            let current = l.id != nil && l.id == currentId
            Card {
                HStack(spacing: 12) {
                    Thumb(url: l.image, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Title("#\(l.ordinal_position.map { String($0) } ?? "—") \(stripHtml(l.name))")
                            if current { Badge(label: "You", tone: .accent) }
                        }
                        Meta("\(l.required_points ?? 0) pts")
                    }
                    Spacer(minLength: 0)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(current ? Color.accent : Color.clear, lineWidth: 2)
            )
        }
    }
}
