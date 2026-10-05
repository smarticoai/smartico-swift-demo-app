import SmarticoPublicAPI
import SwiftUI

/**
 * The points store: the catalogue (getStoreItems) and purchase (buyStoreItem).
 * A purchase reloads the list — `can_buy` and the limits move with the balance.
 */
struct StoreScreen: View {
    @State private var reload = 0
    /**
     * Purchase result per item. (Kotlin keeps one note for the whole screen
     * and so prints it under every card; keyed by item it lands where the
     * button was.)
     */
    @State private var notes: [Int64: String] = [:]

    var body: some View {
        ApiList(
            title: "Store",
            load: {
                let items = try await Smartico.api.getStoreItems()
                let buyable = items.filter { $0.can_buy == true }
                let cheapest = buyable.min { ($0.price ?? 0) < ($1.price ?? 0) }
                demoLog("store: getStoreItems → \(items.count) items, \(buyable.count) can_buy" + (cheapest.map { ", cheapest buyable id=\($0.id ?? 0) price=\(Int($0.price ?? 0)) \($0.purchase_type ?? "")" } ?? ""))
                return items
            },
            reloadKey: reload
        ) { item in
            StoreRow(item: item, note: notes[item.id ?? 0]) { msg in
                notes[item.id ?? 0] = msg
                reload += 1
            }
        }
    }
}

private struct StoreRow: View {
    let item: TStoreItem
    let note: String?
    let onBought: (String) -> Void

    var body: some View {
        Card {
            HStack(alignment: .center, spacing: 0) {
                Thumb(url: item.image, size: 48)
                Spacer().frame(width: 12)
                VStack(alignment: .leading, spacing: 2) {
                    Title(stripHtml(item.name))
                    Meta("\(Int(item.price ?? 0)) \(item.purchase_type ?? "") · \(item.type ?? "")")
                    if item.can_buy == true {
                        ActionButton(label: "Buy", onResult: onBought) {
                            let id = item.id ?? 0
                            let r = try await Smartico.api.buyStoreItem(item_id: id)
                            demoLog("store: buyStoreItem(item_id: \(id)) → err_code=\(r.err_code.map { String($0) } ?? "nil") err_message=\(r.err_message ?? "nil")")
                            return r.err_code ?? 0 == 0 ? "Bought ✓" : (r.err_message ?? "err \(r.err_code.map { String($0) } ?? "")")
                        }
                        .accessibilityIdentifier("store-buy-\(item.id ?? 0)")
                        .padding(.top, 6)
                    }
                    if let note = note { Meta(note) }
                }
                Spacer(minLength: 0)
            }
        }
    }
}
