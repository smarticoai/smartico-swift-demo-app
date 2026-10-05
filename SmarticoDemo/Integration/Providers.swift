import Foundation
import GoogleSignIn
import UIKit

/**
 * Google sign-in.
 *
 * Google is registered against this app's bundle id, which is why the demo
 * deliberately reuses the RN demo's bundle id (`ai.smartico.rnexpo`): the
 * Google Cloud project already has an iOS OAuth client for it. The client ids
 * live in Info.plist (`GIDClientID`, `GIDServerClientID`, written by
 * project.yml), where GoogleSignIn reads them itself.
 */
@MainActor
enum Providers {
    // The backend verifies the Google id_token's `aud` against this web client
    // id, so it must be the WEB client — not the iOS one. On iOS it is passed as
    // the `serverClientID`, which makes Google issue the id_token for it.
    private static let GOOGLE_WEB_CLIENT_ID =
        "259966498344-spl923rp3lgokku9km7jckaj5s8ndin8.apps.googleusercontent.com"
    private static let GOOGLE_IOS_CLIENT_ID =
        "259966498344-e797rqpem16mg72kelqp3bugs49k53vh.apps.googleusercontent.com"

    /**
     * Google sign-in through GoogleSignIn-iOS. It presents Google's own web
     * sheet (ASWebAuthenticationSession) and comes back through the reversed
     * client id URL scheme, which SmarticoDemoApp hands to `GIDSignIn.handle`.
     *
     * "Sign in with Google" (not the silent restore): always shows the account
     * chooser, so logging out really means the next login can pick a different
     * account.
     */
    static func signInGoogle() async throws -> Auth.ProviderResult {
        guard let presenter = topViewController() else {
            throw Auth.AuthError(message: "No window to present Google sign-in from")
        }
        let signIn = GIDSignIn.sharedInstance
        if signIn.configuration == nil {
            signIn.configuration = GIDConfiguration(clientID: GOOGLE_IOS_CLIENT_ID, serverClientID: GOOGLE_WEB_CLIENT_ID)
        }
        let result = try await signIn.signIn(withPresenting: presenter)
        let user = result.user
        guard let idToken = user.idToken?.tokenString else {
            throw Auth.AuthError(message: "Google returned no id_token")
        }
        return Auth.ProviderResult(
            provider_id: Auth.PROVIDER_GGL,
            // the backend keys users on Google's numeric account id, which only
            // exists inside the token — the credential itself exposes the email
            provider_user_id: subjectOf(idToken),
            provider_token: idToken,
            email: user.profile?.email ?? "",
            profile: Auth.SocialProfile(
                firstName: user.profile?.givenName ?? "",
                lastName: user.profile?.familyName ?? "",
                name: user.profile?.name ?? "",
                picture: user.profile?.imageURL(withDimension: 256)?.absoluteString ?? ""
            )
        )
    }

    /** `sub` claim of a JWT — the stable per-account id. */
    nonisolated static func subjectOf(_ idToken: String) -> String {
        let parts = idToken.components(separatedBy: ".")
        if parts.count < 2 { return "" }
        var b64 = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let data = Data(base64Encoded: b64) else { return "" }
        let payload = String(decoding: data, as: UTF8.self)
        guard let m = payload.range(of: "\"sub\"\\s*:\\s*\"[^\"]+\"", options: .regularExpression) else { return "" }
        let pair = String(payload[m])
        let value = pair.components(separatedBy: "\"").dropLast().last ?? ""
        return value
    }

    /**
     * Forget the Google session on logout, so the next login shows the account
     * chooser instead of silently reusing the previous account.
     */
    static func signOut() {
        GIDSignIn.sharedInstance.signOut()
    }

    /** The view controller Google's sheet is presented from. */
    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap { $0.windows }.first { $0.isKeyWindow } ?? scenes.first?.windows.first
        var top = window?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
