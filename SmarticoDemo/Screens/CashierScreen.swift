import SwiftUI

/**
 * Cashier, ported from the web fake-casino: quick amounts, cosmetic payment
 * methods, deposit fires `acc_deposit_approved` to the demo backend. Withdraw
 * is cosmetic there too — it fires nothing.
 */
struct CashierScreen: View {
    let onClose: () -> Void

    @ObservedObject private var economy = Economy.shared
    @State private var amount = 50
    @State private var method = 0
    @State private var note: String?

    private static let QUICK_AMOUNTS = [50, 100, 500, 1000]
    private static let METHODS = ["💳 Master Card", "💳 Visa", "🏦 Via Bank", "💸 Wise"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Cashier").font(.system(size: 22, weight: .bold)).foregroundColor(.white)
                    Spacer()
                    Button(action: onClose) {
                        Text("✕").font(.system(size: 20)).foregroundColor(.muted)
                    }
                    .accessibilityLabel("Close cashier")
                }
                Meta(String(format: "Current balance  €%.2f", economy.balance))
                    .accessibilityIdentifier("cashier-balance")

                Card {
                    Title("Amount")
                    HStack(spacing: 8) {
                        ForEach(CashierScreen.QUICK_AMOUNTS, id: \.self) { q in
                            Button { amount = q } label: {
                                Text(verbatim: "€\(q)")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(Color.card)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(amount == q ? Color.accent : Color.chromeBorder, lineWidth: 1)
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    }
                    .padding(.top, 8)
                    Text("🎁 Get an extra 180% bonus on deposits of €500+")
                        .font(.system(size: 12))
                        .foregroundColor(.gold)
                        .padding(.top, 10)
                }

                Card {
                    Title("Payment method")
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(CashierScreen.METHODS.indices, id: \.self) { i in
                            Button { method = i } label: {
                                Text(method == i ? "◉  \(CashierScreen.METHODS[i])" : "○  \(CashierScreen.METHODS[i])")
                                    .font(.system(size: 13))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 6)
                                    .contentShape(Rectangle())
                            }
                        }
                    }
                    .padding(.top, 8)
                }

                ActionButton(label: "Deposit €\(amount)", onResult: { note = $0 }) {
                    let amount = self.amount
                    let before = Economy.shared.balance
                    try await Economy.shared.reportDeposit(amount: amount)
                    demoLog(String(format: "deposit %d: balance € %.2f → € %.2f", amount, before, Economy.shared.balance))
                    return "Deposit sent — balance updates in a moment ✓"
                }
                if let note = note { Meta(note) }
            }
            .padding(16)
        }
    }
}
