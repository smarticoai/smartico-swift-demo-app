import SwiftUI

/**
 * Login: Google only.
 *
 * The app never invents a user id — Google returns an id_token, the demo
 * backend verifies it and answers with the Smartico `ext_user_id` plus a
 * session token we keep, so the next launch restores the session.
 */
struct LoginScreen: View {
    let onSession: (Auth.SessionUser) -> Void

    @State private var busy = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            Text("🎰").font(.system(size: 56))
            Spacer().frame(height: 8)
            Text("Fakebet")
                .font(.system(size: 30, weight: .bold))
                .foregroundColor(.white)
            Meta("Smartico Swift SDK demo · ICE env4")
            Spacer().frame(height: 28)

            BigButton(label: busy ? "Signing in…" : "Continue with Google", enabled: !busy) {
                error = nil
                busy = true
                Task {
                    do {
                        let provider = try await Providers.signInGoogle()
                        onSession(try await Auth.checkProviderToken(provider))
                    } catch {
                        self.error = error.localizedDescription
                        demoLog("google login failed: \(error.localizedDescription)")
                    }
                    busy = false
                }
            }

            if let error = error {
                Spacer().frame(height: 12)
                Text(error)
                    .font(.system(size: 12))
                    .foregroundColor(.danger)
                    .multilineTextAlignment(.center)
            }

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bg.ignoresSafeArea())
    }
}

private struct BigButton: View {
    let label: String
    var enabled: Bool = true
    var tone: Color = .accent
    let onClick: () -> Void

    var body: some View {
        Button(action: onClick) {
            Text(label)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(enabled ? .white : .muted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(tone)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .disabled(!enabled)
    }
}
