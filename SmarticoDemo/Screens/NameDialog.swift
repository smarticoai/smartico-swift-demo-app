import SmarticoPublicAPI
import SwiftUI

/**
 * Change the public display name (ProfileExtras.kt `NameDialog`) — presented
 * by ProfileScreen as a short sheet. 3–20 characters, as in the RN and Kotlin
 * demos. On success the SDK merges the new name into the public props and
 * emits a props change, so the profile and the header update by themselves.
 */
struct NameDialog: View {
    let onDismiss: () -> Void

    @State private var draft = ""
    @State private var error: String?
    @State private var saving = false
    @State private var seeded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Change display name")
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(.white)
            TextField("Display name", text: $draft)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit(save)
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.bg)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.chromeBorder, lineWidth: 1))
                .accessibilityIdentifier("name-dialog-field")
            Meta("3–20 characters")
            if let error = error {
                Text(error).font(.system(size: 12)).foregroundColor(.danger)
            }
            HStack(spacing: 20) {
                Spacer()
                Button(action: onDismiss) {
                    Text("Cancel").font(.system(size: 15, weight: .semibold)).foregroundColor(.muted)
                }
                Button(action: save) {
                    Text(saving ? "Saving…" : "Save").font(.system(size: 15, weight: .bold)).foregroundColor(.accent)
                }
                .disabled(saving)
                .accessibilityIdentifier("name-dialog-save")
            }
            .padding(.top, 4)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.card.ignoresSafeArea())
        .presentationDetents([.height(260)])
        .onAppear {
            if seeded { return }
            seeded = true
            // Start from the name the user actually sees in the lobby and on the
            // profile card (displayName), not the raw server field: for a fresh
            // account that field is a placeholder derived from the ext id, and
            // editing "697:9fd95fa7…" while the lobby greets you by name is confusing.
            draft = Sdk.shared.displayName()
        }
    }

    private func save() {
        if !(3...20).contains(draft.count) {
            error = "Name must be 3–20 characters"
            return
        }
        let name = draft
        saving = true
        error = nil
        Task {
            demoLog("changeUsername(\"\(name)\") → sending")
            do {
                let stored = try await Smartico.changeUsername(name)
                demoLog("changeUsername ← public_username_custom=\(stored ?? "nil")")
                saving = false
                if stored != nil {
                    onDismiss()
                } else {
                    // the reply carried no name: the server kept the old one
                    error = "The server did not accept this name"
                }
            } catch {
                demoLog("changeUsername failed: \(error)")
                saving = false
                self.error = error.localizedDescription
            }
        }
    }
}
