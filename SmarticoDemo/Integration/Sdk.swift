import CryptoKit
import Foundation
import SmarticoPublicAPI

/**
 * One `[SmarticoDemo]` line on stdout — the demo's own log, next to the SDK's
 * `[Smartico]` lines (Kotlin: `android.util.Log` with the "SmarticoDemo" tag).
 * Flushed right away so `xcrun simctl launch --console` shows it live.
 */
func demoLog(_ line: String) {
    print("[SmarticoDemo] \(line)")
    fflush(stdout)
}

/**
 * SDK listener callbacks are delivered on the main queue, but the callback type
 * carries no actor isolation the compiler can see. This runs `body` on the main
 * actor: synchronously when we are already on the main thread (the normal
 * case), otherwise as a main-actor task.
 */
func onMainActor(_ body: @escaping @MainActor () -> Void) {
    if Thread.isMainThread {
        MainActor.assumeIsolated { body() }
    } else {
        Task { @MainActor in body() }
    }
}

/**
 * Smartico wiring for the demo — ICE env4, the same label the React Native
 * demo uses.
 *
 * The label's hash salt is the literal string "null", so the identify hash can
 * be computed here. A production app NEVER does this: the operator's backend
 * computes it with the real (secret) salt and the app just forwards it.
 */
@MainActor
final class Sdk: ObservableObject {
    static let shared = Sdk()

    nonisolated static let LABEL_KEY = "a6e7ac26-c368-4892-9380-96e7ff82cf3e-4"
    nonisolated static let BRAND_KEY = "f86271e6"

    /** Public properties (points, level, avatar…), kept live by props_change. */
    @Published private(set) var props: [String: JSON] = [:]

    /** Flips to true once the server has identified the user. */
    @Published private(set) var identified = false

    /** Bumped whenever the SDK's popup queue changes, so the UI can pump it. */
    @Published private(set) var pendingPopups = 0

    private(set) var extUserId: String = ""

    /**
     * The avatar just applied. setAvatar succeeds before the server pushes the
     * new public properties, so without this the UI keeps showing the old
     * picture until some later push happens to carry the new one.
     */
    @Published private(set) var avatar: String?

    /** Current avatar URL: the freshly applied one, else what props report. */
    func avatarUrl() -> String? {
        avatar ?? prop("avatar_url") ?? prop("avatar_id")
    }

    /** Called after a successful setAvatar; also re-reads the server snapshot. */
    func onAvatarApplied(_ url: String) {
        avatar = url
        Task {
            try? await Task.sleep(nanoseconds: 400_000_000) // give the server a moment to store it
            let snapshot = await Smartico.getPublicProps()
            props.merge(snapshot) { _, new in new }
        }
    }

    /** Name from the social login — used until the server has a real one. */
    private(set) var socialName: String?

    /** True once a player has been chosen on the login screen. */
    @Published private(set) var loggedIn = false

    private var started = false

    private init() {}

    func start(_ user: String) {
        if user != extUserId {
            Store.shared.clear() // different player, different data
            avatar = nil
        }
        extUserId = user
        loggedIn = true
        if !started {
            started = true
            // Subscriptions are registered once: the facade re-attaches them to
            // every new connection, so they survive a re-init.
            Smartico.on("identify") { _ in
                onMainActor {
                    let sdk = Sdk.shared
                    sdk.identified = true
                    demoLog("identified as \(sdk.extUserId)")
                    // The token binds to the identified user server-side, so it is
                    // sent here rather than at startup. Repeat identifies (login,
                    // then profile enrichment) are deduped inside Push.register.
                    Push.register(sdk.extUserId)
                    Task { @MainActor in
                        // The full property snapshot lives on the connection after
                        // identify; without merging it here the UI only ever saw
                        // whatever a later props push happened to carry — which is
                        // why the profile showed the raw ext id instead of the name.
                        let snapshot = await Smartico.getPublicProps()
                        sdk.props.merge(snapshot) { _, new in new }
                        demoLog("profile: name=\(sdk.displayName()) points=\(sdk.prop("ach_points_balance") ?? "—") level=\(sdk.prop("ach_level_current") ?? "—") user_id=\(sdk.prop("user_id") ?? "—")")
                    }
                    Store.shared.refreshAll() // full snapshot for the identified user
                }
            }
            Smartico.on("props_change") { msg in
                guard let patch = msg["props"]?.object else { return }
                onMainActor {
                    Sdk.shared.props.merge(patch) { _, new in new }
                }
            }
            // Every fresh engagement (popup / inbox / push) surfaces here.
            Smartico.on("engagement") { msg in
                let at = (msg["activityType"] ?? msg["activity_type"])?.string ?? "nil"
                demoLog("engagement activityType=\(at) uid=\(msg["engagement_uid"]?.string ?? "nil")")
            }
            _ = Smartico.onEngagementsChanged {
                let n = Smartico.pendingEngagements()
                demoLog("popup queue = \(n)")
                onMainActor { Sdk.shared.pendingPopups = n }
            }
            // Server-initiated deep link: the SDK routes it, but only the app
            // can decide it should run — the same uid may also arrive as a
            // popup (cid 110), so it shares the SDK's engagement dedupe.
            Smartico.on("execute_deeplink") { msg in
                let uid = msg["engagement_uid"]?.string ?? ""
                if !uid.isEmpty && Smartico.isDuplicateEngagement(uid) { return }
                let dp = (msg["payload"]?["dp"] ?? msg["dp"])?.string
                guard let dp = dp, !dp.isEmpty else { return }
                demoLog("execute_deeplink → \(dp)")
                onMainActor { Smartico.dp(dp) }
            }

            // "Show this mini-game now" campaign push.
            Smartico.on("show_spin") { msg in
                guard let id = msg["saw_template_id"]?.string else { return }
                onMainActor { Smartico.dp("dp:gf_saw&id=\(id)&standalone=true") }
            }
            // the canonical "missions/badges changed" push — the only signal
            // needed for live progress (points also move, but that arrives as a
            // separate props push and would just double the fetch)
            Smartico.on("reload_achievements") { _ in
                demoLog("achievements changed (server push) → reloading")
                onMainActor {
                    Store.shared.refreshMissions()
                    Store.shared.refreshBadges()
                }
            }
        }
        identified = false
        var options = SmarticoOptions(
            brandKey: Sdk.BRAND_KEY,
            getUser: {
                await MainActor.run {
                    let ext = Sdk.shared.extUserId
                    return SmarticoUser(extUserId: ext, hash: Sdk.demoHash(ext))
                }
            },
            debug: true
        )
        #if DEBUG
        // `-traceFrames` dumps every non-ping socket frame (IN/OUT) — how the
        // feature screens prove a mutation request is built right without sending it twice.
        options.traceFrames = LaunchArgs.has("-traceFrames")
        #endif
        Smartico.initialize(labelKey: Sdk.LABEL_KEY, options: options)
    }

    /**
     * A server-generated username echoes the user's ext id (optionally behind a
     * "<label id>:" prefix). That is a placeholder, not a name — the UI should
     * show the social-login name instead, and the enrichment below replaces it.
     */
    nonisolated static func isAutoUsername(_ username: String?, _ extUserId: String) -> Bool {
        guard let username = username, !username.isEmpty else { return true }
        let bare = username.firstIndex(of: ":").map { String(username[username.index(after: $0)...]) } ?? username
        return extUserId.range(of: bare, options: .caseInsensitive) != nil
            || bare.range(of: extUserId, options: .caseInsensitive) != nil
    }

    /** The name to show: real server username, else social name, else the id. */
    func displayName() -> String {
        let username = prop("public_username")
        if !Sdk.isAutoUsername(username, extUserId), let username = username { return username }
        return socialName ?? username ?? extUserId
    }

    /**
     * Seed the demo profile from the social login, the way the web fake-casino
     * does: a fresh user gets an auto-generated username derived from the id, so
     * replace it with the real first name. Best-effort — never blocks login.
     */
    func enrichProfile(_ user: Auth.SessionUser) {
        let firstName = user.profile?.firstName.nonEmpty
        let lastName = user.profile?.lastName.nonEmpty
        let emailName = user.email.flatMap { $0.components(separatedBy: "@").first?.nonEmpty }
        guard let first = firstName ?? lastName ?? emailName else { return }
        socialName = [firstName, lastName].compactMap { $0 }.joined(separator: " ").nonEmpty ?? first
        Task {
            // wait for identify so public props exist
            for _ in 0..<50 {
                if !props.isEmpty { break }
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
            // only overwrite the placeholder name, never a real one
            if !Sdk.isAutoUsername(prop("public_username"), user.user_ext_id) { return }
            do {
                try await Smartico.event("demo_personal_details_update", payload: [
                    "firstName": .string(first),
                    "currency": "EUR",
                ])
                if let last = lastName {
                    try await Smartico.event("demo_personal_details_update", payload: ["lastName": .string(last)])
                }
                if let email = user.email?.nonEmpty {
                    try await Smartico.event("demo_personal_details_update", payload: ["playerEMail": .string(email)])
                }
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                if extUserId == user.user_ext_id { start(user.user_ext_id) } // re-identify so the name lands
            } catch {
                demoLog("profile enrichment failed: \(error.localizedDescription)")
            }
        }
    }

    /**
     * Reset demo progress. The backend clones the player under a fresh
     * ext_user_id (same login session), so points, missions and levels start
     * over; we then re-identify as that new user.
     */
    func resetProgress() async -> String {
        guard let user = try? await Auth.resetProgress() else { return "No session to reset" }
        start(user.user_ext_id)
        enrichProfile(user) // the clone starts with a placeholder name too
        return "Progress reset ✓"
    }

    /** Drop the session and go back to the login screen. */
    func logout() {
        Auth.clearCookie()
        // forget the Google session, otherwise the next
        // login silently reuses the previous account
        Providers.signOut()
        Smartico.logout()
        identified = false
        loggedIn = false
        props = [:]
        avatar = nil
        Store.shared.clear()
    }

    func prop(_ key: String) -> String? {
        props[key]?.string
    }

    /** md5("<user>:<salt>:<ts>") + ":" + ts, with the demo label's "null" salt. */
    nonisolated static func demoHash(_ user: String) -> String {
        let ts = Int64(Date().timeIntervalSince1970) * 1000 + 24 * 3600 * 1000
        let digest = Insecure.MD5.hash(data: Data("\(user):null:\(ts)".lowercased().utf8))
        let md5 = digest.map { String(format: "%02x", $0) }.joined()
        return "\(md5):\(ts)"
    }
}

extension String {
    /** Kotlin's `takeIf { it.isNotEmpty() }`. */
    var nonEmpty: String? { isEmpty ? nil : self }
}
