import Foundation
import SmarticoPublicAPI

/**
 * The demo's fake money, exactly as the web fake-casino does it.
 *
 * The client NEVER moves balances itself: money events are authored by the ICE
 * demo backend (SL_SERVER), which recomputes the wallet; the app just polls
 * `wallet-debit` with a zero amount to read the current balance back.
 */
@MainActor
final class Economy: ObservableObject {
    static let shared = Economy()

    private static let SL_SERVER = "https://dvm0p9vsezqr2.cloudfront.net/social-login"
    private static let CURRENCY = "EUR"
    private static let POLL_NS: UInt64 = 2_000_000_000

    /** Events the backend must author (they move money). Everything else goes over the socket. */
    private static let SERVER_EVENTS: Set<String> = [
        "acc_deposit_approved",
        "casino_bet_win",
        "sport_bet_open",
        "sport_bet_settled",
        "demo_fx_open_position",
        "demo_fx_close_position",
    ]

    @Published private(set) var balance: Double = 0
    @Published private(set) var bonus: Double = 0

    private var polling = false

    private init() {}

    /** Start the 2s balance poll (no-op if already running). */
    func startPolling() {
        if polling { return }
        polling = true
        Task { @MainActor in
            while true {
                await refresh()
                try? await Task.sleep(nanoseconds: Economy.POLL_NS)
            }
        }
    }

    /** One balance read: a zero-amount debit is the demo backend's "get balance". */
    func refresh() async {
        guard let userId = userIdProp() else { return } // not identified yet
        guard let r = await post("wallet-debit", [
            "user_id": JSON(userId),
            "currency": .string(Economy.CURRENCY),
            "amount_real": 0,
            "amount_bonus": 0,
        ]) else { return }
        if let v = r["amount_real"]?.double { balance = v }
        if let v = r["amount_bonus"]?.double { bonus = v }
    }

    /** A casino spin: bet and win are settled by the backend. */
    func reportSpin(gameExtId: String, bet: Int, win: Int) async throws {
        try await submit("casino_bet_win", [
            "casino_last_bet_id": .string(randomId()),
            "casino_last_bet_dt": JSON(nowMillis()),
            "casino_last_bet_game_name": .string(gameExtId),
            "casino_last_bet_amount": JSON(bet),
            "casino_last_win_amount": JSON(win),
        ])
    }

    /** A cashier deposit. */
    func reportDeposit(amount: Int) async throws {
        try await submit("acc_deposit_approved", [
            "acc_last_deposit_date": JSON(nowMillis()),
            "acc_last_deposit_amount": JSON(amount),
            "acc_last_transaction_id": .string(randomId()),
        ])
    }

    /**
     * Route one event: money events go to the backend (which then moves the
     * wallet), everything else straight over the Smartico socket.
     */
    private func submit(_ eventName: String, _ payload: JSONObject) async throws {
        if Economy.SERVER_EVENTS.contains(eventName) {
            var withUser = payload
            if let userId = userIdProp() { withUser["user_id"] = JSON(userId) }
            _ = await post("sendEventIce", [
                "eventName": .string(eventName),
                "payload": .object(withUser),
                "user_ext_id": .string(Sdk.shared.extUserId),
            ])
            await refresh() // the balance moved server-side — read it back now
        } else {
            try await Smartico.event(eventName, payload: payload)
        }
    }

    /** The numeric Smartico user id (from IDENTIFY_RESPONSE, mirrored into props). */
    private func userIdProp() -> Int64? {
        Sdk.shared.prop("user_id").flatMap { Double($0) }.map { Int64($0) }
    }

    private func randomId() -> String {
        String(Int64.random(in: 1_000_000..<9_999_999), radix: 36)
    }

    private func post(_ method: String, _ body: JSONObject) async -> JSONObject? {
        // every call to this backend is scoped by label + brand, exactly
        // like the web demo's API.requestServer
        var payload: JSONObject = [
            "label_public_key": .string(Sdk.LABEL_KEY),
            "brand_public_key": .string(Sdk.BRAND_KEY),
        ]
        for (k, v) in body { payload[k] = v }
        guard let url = URL(string: "\(Economy.SL_SERVER)/\(method)") else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = JSON.object(payload).data()
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let text = String(decoding: data, as: UTF8.self)
            if !(200..<300).contains(code) {
                demoLog("\(method) HTTP \(code): \(text)")
            } else if method != "wallet-debit" {
                demoLog("\(method) → \(text)")
            }
            return (try? JSON.parse(data))?.object
        } catch {
            demoLog("\(method) failed: \(error.localizedDescription)")
            return nil
        }
    }
}
