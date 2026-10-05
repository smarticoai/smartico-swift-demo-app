import Foundation
import SmarticoPublicAPI

/**
 * Google login against the demo backend, ported from the RN demo.
 *
 * Flow: Google hands us an id_token, the backend verifies
 * it and answers with the Smartico `user_ext_id` plus a `cookie_token` we store
 * to restore the session on the next launch. The app never invents user ids —
 * the backend owns that mapping.
 */
enum Auth {
    private static let SL_SERVER = "https://dvm0p9vsezqr2.cloudfront.net/social-login"
    private static let COOKIE_KEY = "sm_cookie_token"

    /** Provider id the backend expects for Google. */
    static let PROVIDER_GGL = 2

    struct SocialProfile: Codable, Hashable {
        var firstName: String = ""
        var lastName: String = ""
        var name: String = ""
        var picture: String = ""

        init(firstName: String = "", lastName: String = "", name: String = "", picture: String = "") {
            self.firstName = firstName
            self.lastName = lastName
            self.name = name
            self.picture = picture
        }

        // ignoreUnknownKeys + defaults, like the Kotlin Json config
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            firstName = (try? c.decodeIfPresent(String.self, forKey: .firstName)) ?? ""
            lastName = (try? c.decodeIfPresent(String.self, forKey: .lastName)) ?? ""
            name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
            picture = (try? c.decodeIfPresent(String.self, forKey: .picture)) ?? ""
        }
    }

    /** What a provider sign-in produces, ready to POST to checkProviderToken. */
    struct ProviderResult: Codable, Hashable {
        var provider_id: Int
        var provider_user_id: String
        var provider_token: String
        var email: String = ""
        var profile: SocialProfile = SocialProfile()
    }

    struct SessionUser: Codable, Hashable {
        var user_ext_id: String
        var email: String? = nil
        var profile: SocialProfile? = nil
    }

    struct AuthError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /**
     * POST to the social-login server. Every call carries the label/brand keys.
     * A native app has no browser cookie jar, so the session token travels in
     * the body and we persist it ourselves.
     */
    private static func request(_ method: String, _ body: JSONObject) async throws -> JSON {
        var payload: JSONObject = [
            "label_public_key": .string(Sdk.LABEL_KEY),
            "brand_public_key": .string(Sdk.BRAND_KEY),
        ]
        for (k, v) in body { payload[k] = v }
        guard let url = URL(string: "\(SL_SERVER)/\(method)") else { throw AuthError(message: "bad url") }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = JSON.object(payload).data()
        let (data, response) = try await URLSession.shared.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if !(200..<300).contains(code) { throw AuthError(message: "\(method) failed: HTTP \(code)") }
        if data.isEmpty { return .null }
        return (try? JSON.parse(data)) ?? .null
    }

    /** Exchange a provider token for a Smartico user. */
    static func checkProviderToken(_ p: ProviderResult) async throws -> SessionUser {
        let encoded = try JSONEncoder().encode(p)
        let body = (try JSON.parse(encoded)).object ?? [:]
        let r = try await request("checkProviderToken", body)
        let ext = r["user_ext_id"]?.string
        let cookie = r["cookie_token"]?.string
        guard let ext = ext, !ext.isEmpty, let cookie = cookie, !cookie.isEmpty else {
            throw AuthError(message: r["err_message"]?.string ?? "Login rejected by server")
        }
        demoLog("login ok: user=\(ext), session token stored")
        saveCookie(cookie)
        return SessionUser(user_ext_id: ext, email: p.email, profile: p.profile)
    }

    /** Restore a previous session (called on launch). Nil when there is none. */
    static func restore() async -> SessionUser? {
        guard let cookie = cookie() else { return nil }
        do {
            let r = try await request("checkCookieToken", ["cookie_token": .string(cookie)])
            guard let ext = r["user_ext_id"]?.string, !ext.isEmpty else {
                demoLog("session restore: server returned no user (\(r.jsonString()))")
                return nil
            }
            return SessionUser(user_ext_id: ext, email: r["email"]?.string, profile: parseProfile(r["profile"]))
        } catch {
            demoLog("session restore failed: \(error.localizedDescription)")
            return nil
        }
    }

    /**
     * The backend writes the profile with JSON.stringify, so it usually comes
     * back as a STRING — but not always. Keep it raw and unpack it here.
     */
    private static func parseProfile(_ raw: JSON?) -> SocialProfile? {
        guard let raw = raw, !raw.isNull else { return nil }
        let data: Data
        if case .string(let s) = raw {
            data = Data(s.utf8)
        } else {
            data = raw.data()
        }
        return try? JSONDecoder().decode(SocialProfile.self, from: data)
    }

    /** Reset demo progress: the backend re-guids the user behind the same session. */
    static func resetProgress() async throws -> SessionUser? {
        guard let cookie = cookie() else { return nil }
        _ = try await request("duplicateUser", ["cookie_token": .string(cookie)])
        return await restore()
    }

    static func cookie() -> String? {
        UserDefaults.standard.string(forKey: COOKIE_KEY)
    }

    private static func saveCookie(_ token: String) {
        UserDefaults.standard.set(token, forKey: COOKIE_KEY)
    }

    static func clearCookie() {
        UserDefaults.standard.removeObject(forKey: COOKIE_KEY)
    }
}
