import GoogleSignIn
import SmarticoPublicAPI
import SwiftUI
import UIKit
@preconcurrency import UserNotifications

@main
struct SmarticoDemoApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        // stdout is a pipe under `simctl launch --console`: line-buffer it so the
        // demo's and the SDK's log lines show up as they happen.
        setvbuf(stdout, nil, _IOLBF, 0)
        DeepLinks.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
                .onOpenURL { url in
                    // Google's sign-in sheet comes back through the reversed
                    // client id scheme; everything else is our dp entry point.
                    if GIDSignIn.sharedInstance.handle(url) { return }
                    if !DeepLinks.handleIncomingUrl(url) {
                        demoLog("ignored url \(url.absoluteString)")
                    }
                }
        }
    }
}

/**
 * The root switch (MainActivity.setContent): restoring a stored session /
 * login / the app with campaign popups floating above it.
 */
struct RootView: View {
    @ObservedObject private var sdk = Sdk.shared

    // A stored session token means the user already signed in on this
    // device — resolve it with the backend before showing the login.
    @State private var restoring = Auth.cookie() != nil
    @State private var bootstrapped = false

    var body: some View {
        ZStack {
            Color.bg.ignoresSafeArea()
            if restoring {
                Loading()
            } else if !sdk.loggedIn {
                LoginScreen(onSession: RootView.activate)
            } else {
                AppNav()
                // Campaign popups float above everything, like in the web app
                PopupHost()
            }
        }
        .task {
            if bootstrapped { return }
            bootstrapped = true
            if restoring {
                if let user = await Auth.restore() {
                    RootView.activate(user)
                }
                restoring = false
            }
        }
        // Deep-link entry point: a link handed to the app before login runs
        // as soon as a player is logged in.
        // (onChange, not onReceive: SwiftUI re-subscribes a fresh publisher on
        // every body update, and @Published replays its value to each one.)
        .onChange(of: sdk.loggedIn) { loggedIn in
            if loggedIn { DeepLinks.onLoggedIn() } else { AppRouter.shared.reset() }
        }
        // A push tap can cold-start the app: the deep link is parked until
        // the SDK has identified the user, otherwise it would route into a
        // screen with no session behind it.
        .onChange(of: sdk.identified) { identified in
            if !identified { return }
            Push.flushPendingDp()
            Push.requestPermissionIfNeeded()
            // the demo backend owns the money; poll it once identified
            Economy.shared.startPolling()
            DeepLinks.onIdentified()
        }
    }

    /** Mark logged-in: identify with Smartico, then seed the profile. */
    static func activate(_ user: Auth.SessionUser) {
        Sdk.shared.start(user.user_ext_id)
        Sdk.shared.enrichProfile(user)
    }
}

/**
 * Push plumbing (and nothing else — SwiftUI owns the UI). The notification
 * delegate must be set before launch finishes, or a tap that cold-starts the
 * app is never delivered.
 */
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        #if DEBUG
        // `-pushTap <uid>`: feed the tap handler the same userInfo a tap on
        // Tools/push-sample.apns delivers (taps cannot be automated on the simulator).
        if let uid = LaunchArgs.value(after: "-pushTap") {
            let userInfo: [AnyHashable: Any] = [
                "aps": ["alert": ["title": "Your mission is waiting", "body": "Spin today and claim it"]],
                "engagement_uid": uid,
                "message_id": "1",
                "dp": LaunchArgs.value(after: "-pushTapDp") ?? "dp:gf_missions",
            ]
            demoLog("launch argument -pushTap \(uid) → simulated notification tap")
            Push.onTap(userInfo)
        }
        #endif
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Push.onToken(deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Push.onTokenError(error)
    }

    /** Data-only (content-available) pushes, and any push while the app runs. */
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        Push.onDelivered(userInfo)
        completionHandler(.noData)
    }

    /** A push arrived while the app is in the foreground: show it and report it. */
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let title = notification.request.content.title
        let box = UserInfoBox(notification.request.content.userInfo)
        DispatchQueue.main.async {
            demoLog("push received in foreground: \(title)")
            Push.onForegroundDelivery(box.userInfo)
        }
        completionHandler([.banner, .list, .sound])
    }

    /** The user tapped a notification (warm app, or the cold start it caused). */
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let box = UserInfoBox(response.notification.request.content.userInfo)
        DispatchQueue.main.async {
            demoLog("push tapped")
            Push.onTap(box.userInfo)
        }
        completionHandler()
    }
}

/** Carries a notification's userInfo across to the main queue. */
private struct UserInfoBox: @unchecked Sendable {
    let userInfo: [AnyHashable: Any]
    init(_ userInfo: [AnyHashable: Any]) { self.userInfo = userInfo }
}

/**
 * DEBUG launch arguments for driving the app without taps:
 *   -dp <link>            run a deep link once identified
 *   -pushTap <uid>        simulate a tap on a campaign push (dp from -pushTapDp, default dp:gf_missions)
 *   -traceFrames          SDK frame trace (every non-ping IN/OUT frame)
 * e.g. `xcrun simctl launch --console booted ai.smartico.rnexpo -dp dp:gf_missions`
 */
enum LaunchArgs {
    static func has(_ flag: String) -> Bool {
        ProcessInfo.processInfo.arguments.contains(flag)
    }

    static func value(after flag: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        let v = args[i + 1]
        return v.hasPrefix("-") ? nil : v // the next flag, not a value
    }
}
