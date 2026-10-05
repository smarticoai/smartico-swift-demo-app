import SmarticoPublicAPI
import SwiftUI

/**
 * The VIP ladder with the user's position, from getLevels + getCurrentLevel
 * (ProfileExtras.kt `VipScreen`): a current-level card on top of the levels
 * list. The next level and the points still missing come from the same ladder
 * and `ach_points_ever` — the measure `getCurrentLevel` computes progress on.
 */
struct VipScreen: View {
    @ObservedObject private var sdk = Sdk.shared
    @State private var current: TLevelCurrent?
    @State private var next: TLevel?

    var body: some View {
        VStack(spacing: 0) {
            if let current = current {
                let progress = current.progress ?? 0
                Card {
                    HStack(spacing: 12) {
                        Thumb(url: current.image, size: 48)
                        VStack(alignment: .leading, spacing: 2) {
                            SectionLabel("Current level")
                            Title(stripHtml(current.name))
                        }
                        Spacer(minLength: 0)
                    }
                    // the top rung has no "next": the full bar turns green instead
                    ProgressBar(percent: progress, completed: next == nil)
                        .padding(.top, 10)
                    if let next = next {
                        let ever = sdk.props["ach_points_ever"]?.double.map { Int64($0) } ?? 0
                        let left = max(0, (next.required_points ?? 0) - ever)
                        Meta("\(Int(progress))% to the next level")
                            .padding(.top, 6)
                        Meta("Next: \(stripHtml(next.name)) · \(left) pts left")
                            .padding(.top, 2)
                    } else {
                        Meta("Top level reached ✓").padding(.top, 6)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
            }
            LevelsScreen()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task {
            do {
                let level = try await Smartico.api.getCurrentLevel()
                current = level
                let ladder = try await Smartico.api.getLevels().sorted { ($0.required_points ?? 0) < ($1.required_points ?? 0) }
                next = ladder.first { ($0.required_points ?? 0) > (level?.required_points ?? Int64.max) }
                demoLog("vip: current=\(level?.name ?? "nil") progress=\(level?.progress.map { String(format: "%.1f", $0) } ?? "nil") next=\(next?.name ?? "nil")")
            } catch {
                demoLog("vip: getCurrentLevel failed: \(error)")
            }
        }
    }
}
