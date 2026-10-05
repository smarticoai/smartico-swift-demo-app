import Foundation
import SmarticoPublicAPI
import UIKit
import UserNotifications

/**
 * Campaign push notifications.
 *
 * Two halves that are easy to confuse: APNs delivers the message to the device,
 * and Smartico wants to know what happened to it. The SDK owns the Smartico
 * half — token registration (cid 1003) and the lifecycle reports — so this file
 * is only the iOS plumbing around it.
 *
 * Delivery depends on the app's state. In the foreground iOS hands the push to
 * `willPresent` before showing it, which is the only case where we can report
 * an impression at display time. In the background the system draws the banner
 * without our code running at all — there the tap is the first thing we see,
 * which is why `onTap` retro-reports the earlier events.
 *
 * Payload keys are the FCM data keys of the Android demo, reused verbatim at
 * the APNs top level: `engagement_uid`, `message_id`, `dp` (or `action`),
 * plus the alert's title/body in `aps`.
 *
 * Real delivery needs an Apple Developer team and an APNs key; on the simulator
 * the path is driven with `xcrun simctl push booted ai.smartico.rnexpo Tools/push-sample.apns`.
 */
@MainActor
enum Push {
    /**
     * One report per (engagement, event type). A tap retro-reports delivered
     * and impression, which the foreground path may already have sent.
     */
    private static var reported = Set<String>()

    /** Last (user, token) pair sent, so repeated identifies don't re-send it. */
    private static var lastRegistered: String?

    /** The APNs device token (lowercase hex) once iOS has handed it over. */
    private static var apnsToken: String?

    /**
     * A tap's deep link, held until the app can actually act on it. A tap that
     * cold-starts the app arrives long before login and navigation exist.
     */
    private static var pendingDp: String?

    /** A permission request is in flight (one system prompt at a time). */
    private static var asking = false

    /**
     * Get the APNs token and hand it to Smartico. Safe to call after every
     * identify: the SDK queues the registration until the user is identified,
     * and an unchanged (user, token) pair is skipped here.
     *
     * iOS gives the token asynchronously (AppDelegate →
     * `onToken`); the first call only asks for it. Registering for remote
     * notifications needs no user permission — the permission only governs
     * whether banners are shown.
     *
     * Best-effort by design — no APNs entitlement (an unsigned simulator
     * build), or a user who declined notifications, end up here and must not
     * break the app.
     */
    static func register(_ extUserId: String) {
        if extUserId.isEmpty { return }
        guard let token = apnsToken else {
            UIApplication.shared.registerForRemoteNotifications()
            return
        }
        let key = "\(extUserId):\(token)"
        if key == lastRegistered { return }
        lastRegistered = key
        Smartico.registerPushToken(token, platform: PushPlatform.NATIVE_IOS, appPackageId: Bundle.main.bundleIdentifier)
        demoLog("push token registered for \(extUserId) — \(token.prefix(16))…")
    }

    /**
     * iOS handed over (or rotated) the device token, which can happen without a
     * login. The SDK queues the registration until a user is identified, so
     * sending it straight away is safe; with nobody logged in it waits for the
     * next identify.
     */
    static func onToken(_ deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        apnsToken = hex
        demoLog("APNs token received — \(hex.prefix(16))…")
        let ext = Sdk.shared.extUserId
        if ext.isEmpty { return }
        register(ext)
    }

    static func onTokenError(_ error: Error) {
        demoLog("push token unavailable: \(error.localizedDescription)")
    }

    /**
     * Ask for the alert permission. Declining is a normal outcome — campaigns
     * simply never show on this device — so there is nothing to handle here.
     * Called after identify (same trigger as the Android POST_NOTIFICATIONS
     * prompt); iOS shows the prompt only once and answers from the stored
     * decision afterwards.
     */
    static func requestPermissionIfNeeded() {
        if asking { return }
        asking = true
        Task { @MainActor in
            defer { asking = false }
            if await allowed() { return }
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            if settings.authorizationStatus != .notDetermined { return } // already declined
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            demoLog("notification permission \(granted ? "granted" : "declined")")
        }
    }

    /** True once the user has allowed notifications to be shown. */
    static func allowed() async -> Bool {
        let s = await UNUserNotificationCenter.current().notificationSettings()
        switch s.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        default: return false
        }
    }

    /** Campaign payload → the reference Smartico identifies the engagement by. */
    nonisolated static func refFrom(_ userInfo: [AnyHashable: Any]) -> PushEngagementRef? {
        guard let uid = text(userInfo["engagement_uid"]) ?? text(userInfo["engagementUid"]), !uid.isEmpty else {
            return nil
        }
        return PushEngagementRef(
            engagementUid: uid,
            messageId: text(userInfo["message_id"]) ?? text(userInfo["messageId"]),
            action: text(userInfo["dp"]) ?? text(userInfo["action"])
        )
    }

    /** A payload value as text (APNs JSON may carry ids as numbers). */
    nonisolated private static func text(_ v: Any?) -> String? {
        switch v {
        case let s as String: return s
        case let n as NSNumber: return n.stringValue
        default: return nil
        }
    }

    static func report(_ type: PushEngagementEventType, _ ref: PushEngagementRef) {
        let key = "\(ref.engagementUid):\(type.wire)"
        if reported.contains(key) { return }
        reported.insert(key)
        demoLog("push \(type.wire) \(ref.engagementUid) → SDK")
        // Queued by the SDK until identify, so a cold-start tap still reports.
        Smartico.reportPushEngagement(type, ref: ref)
    }

    /**
     * A push arrived while the app is in the foreground (`willPresent`). We are
     * about to show it ourselves, so display and delivery coincide here.
     */
    static func onForegroundDelivery(_ userInfo: [AnyHashable: Any]) {
        guard let ref = refFrom(userInfo) else { return }
        report(.delivered, ref)
        Task { @MainActor in
            if await allowed() { report(.impression, ref) }
        }
    }

    /**
     * A push woke the app (`didReceiveRemoteNotification`, data-only or any
     * push while running). Delivered, not necessarily seen — the impression is
     * reported where it is shown (`onForegroundDelivery`) or tapped (`onTap`).
     */
    static func onDelivered(_ userInfo: [AnyHashable: Any]) {
        guard let ref = refFrom(userInfo) else { return }
        report(.delivered, ref)
    }

    /**
     * A notification was tapped. The tap proves the whole chain, so it
     * retro-reports what display time could not, and parks the deep link for
     * `flushPendingDp` to run once the app is identified.
     */
    static func onTap(_ userInfo: [AnyHashable: Any]) {
        guard let ref = refFrom(userInfo) else { return }
        report(.delivered, ref)
        report(.impression, ref)
        report(.action, ref)
        if let dp = ref.action, !dp.isEmpty { pendingDp = dp }
        if Sdk.shared.identified { flushPendingDp() }
    }

    /** Run a parked deep link. Call once the SDK reports the user identified. */
    static func flushPendingDp() {
        guard let dp = pendingDp else { return }
        pendingDp = nil
        demoLog("push deep link → \(dp)")
        Smartico.dp(dp)
    }
}
