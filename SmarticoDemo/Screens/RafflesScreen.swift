import SmarticoPublicAPI
import SwiftUI

/**
 * Raffles (Screens.kt `RafflesScreen`): `getRaffles()`, one card per raffle
 * with its banner, ticket count and number of draws; a tap opens the draws.
 */
struct RafflesScreen: View {
    var body: some View {
        ApiList(title: "Raffles", load: {
            let list = try await Smartico.api.getRaffles()
            demoLog("raffles: \(list.count) — " + list.map { r in
                "\(r.id ?? 0):\(stripHtml(r.name)) draws=\(r.draws?.count ?? 0) tickets=\(r.current_tickets_count ?? 0)/\(r.max_tickets_count ?? 0)"
            }.joined(separator: " | "))
            return list
        }) { r in
            Button {
                AppRouter.shared.navigate(.raffle(raffleId: r.id ?? 0))
            } label: {
                Card {
                    // the raffle banner is a wide strip (890:193), like in RN
                    let banner = r.image_url_mobile?.nonEmpty ?? r.image_url
                    if let banner = banner, !banner.isEmpty, let u = URL(string: banner) {
                        Color.chromeBorder
                            .aspectRatio(890.0 / 193.0, contentMode: .fit)
                            .overlay(AsyncImage(url: u) { $0.resizable().scaledToFill() } placeholder: { Color.clear }.allowsHitTesting(false).accessibilityHidden(true))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        Spacer().frame(height: 8)
                    }
                    Title(stripHtml(r.name))
                    if !stripHtml(r.description).isEmpty {
                        Text(stripHtml(r.description))
                            .font(.system(size: 12))
                            .foregroundColor(.muted)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer().frame(height: 8)
                    HStack(spacing: 0) {
                        Badge(label: "\(r.draws?.count ?? 0) draws", tone: .accent)
                        Spacer().frame(width: 8)
                        Meta("Tickets: \(r.current_tickets_count ?? 0)/\(r.max_tickets_count ?? 0)")
                        Spacer(minLength: 0)
                        Text("Draws ›")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.accent)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}
