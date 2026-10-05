import SmarticoPublicAPI
import SwiftUI

/**
 * Points leaderboard for the running day (Screens.kt `LeaderboardScreen`):
 * `getLeaderBoard(DAILY)`, one ranked card per player.
 */
struct LeaderboardScreen: View {
    var body: some View {
        ApiList(title: "Leaderboard", load: {
            let board = try await Smartico.api.getLeaderBoard(periodType: LeaderBoardPeriodType.DAILY)
            let users = board?.users ?? []
            demoLog("leaderboard DAILY: board_id=\(board?.board_id.map { "\($0)" } ?? "nil") users=\(users.count) me=\(board?.me.map { "#\($0.position ?? 0) \($0.points ?? 0) pts" } ?? "nil")")
            return users
        }) { u in
            Card {
                HStack(spacing: 0) {
                    Text(verbatim: "#\(u.position ?? 0)")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.accent)
                    Spacer().frame(width: 10)
                    Thumb(url: u.avatar_url, size: 32)
                    Spacer().frame(width: 10)
                    VStack(alignment: .leading, spacing: 0) {
                        Title((u.public_username ?? "player") + (u.is_me == true ? "  (you)" : ""))
                        Meta("\(u.points ?? 0) pts")
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}
