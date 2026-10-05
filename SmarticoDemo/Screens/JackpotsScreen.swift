import SmarticoPublicAPI
import SwiftUI

/**
 * Jackpots (Screens.kt `JackpotsScreen`): `jackpotGet()`, the pot and player
 * count per jackpot, and a Join button (`jackpotOptIn`) until the user is in.
 * A result reloads the list so the card flips to "you're in ✓".
 */
struct JackpotsScreen: View {
    @State private var reload = 0
    /** Last opt-in result, per jackpot (jp_template_id). */
    @State private var notes: [Int64: String] = [:]

    var body: some View {
        ApiList(title: "Jackpots", load: {
            let list = try await Smartico.api.jackpotGet()
            demoLog("jackpots: \(list.count) — " + list.map { j in
                "\(j.jp_template_id ?? 0):\(stripHtml(j.jp_public_meta?.name)) pot=\(j.pot?.current_pot_amount_user_currency ?? 0) \(j.user_currency ?? "") opted_in=\(j.is_opted_in == true)"
            }.joined(separator: " | "))
            return list
        }, reloadKey: reload) { j in
            let id = j.jp_template_id ?? 0
            Card {
                Title(stripHtml(j.jp_public_meta?.name))
                Meta("pot \(j.pot?.current_pot_amount_user_currency.map { "\($0)" } ?? "0") \(j.user_currency ?? "") · \(j.registration_count ?? 0) players")
                if j.is_opted_in != true {
                    Spacer().frame(height: 6)
                    ActionButton(label: "Join", onResult: { notes[id] = $0; reload += 1 }) {
                        let r = try await Smartico.api.jackpotOptIn(jp_template_id: id)
                        demoLog("jackpotOptIn(jp_template_id: \(id)) → errCode=\(r.errCode.map { "\($0)" } ?? "nil") errMsg=\(r.errMsg ?? "nil")")
                        return r.errCode == 0 ? "Joined ✓" : r.errMsg ?? "err \(r.errCode.map { "\($0)" } ?? "nil")"
                    }
                } else {
                    Meta("you're in ✓")
                }
                if let note = notes[id] { Meta(note) }
            }
        }
    }
}
