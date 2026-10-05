import SmarticoPublicAPI
import SwiftUI

/**
 * Avatar picker: the operator's catalog, the user's AI-generated ones, and the
 * prompt list that drives new generations (ProfileExtras.kt `AvatarPickerScreen`).
 */
struct AvatarPickerScreen: View {
    let onClose: () -> Void

    @ObservedObject private var sdk = Sdk.shared
    @State private var reload = 0
    @State private var catalog: [TAvatarDefinition] = []
    @State private var customized: [TAvatarCustomized] = []
    @State private var prompts: [TAvatarPrompt] = []
    @State private var loading = true
    @State private var note: String?
    @State private var genNote: String?
    @State private var generating = false
    @State private var generated: GeneratedAvatar?
    @State private var promptId: Int64?
    // Which avatar is active: is_in_use is not filled in on every label, so it
    // is seeded from the profile props and updated locally after setAvatar.
    @State private var activeRealId: Int64?
    @State private var seeded = false

    private let grid = Array(repeating: GridItem(.fixed(64), spacing: 8), count: 4)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Avatar").font(.system(size: 22, weight: .bold)).foregroundColor(.white)
                    Spacer()
                    Button(action: onClose) { Text("✕").font(.system(size: 20)).foregroundColor(.muted) }
                }
                .padding(.bottom, 12)

                if loading {
                    Loading().frame(height: 240)
                } else {
                    if let note = note { Meta(note).padding(.bottom, 8) }
                    catalogCard
                    aiCard.padding(.top, 12)
                    if !customized.isEmpty { customizedCard.padding(.top, 12) }
                }
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .onAppear {
            if seeded { return }
            seeded = true
            activeRealId = sdk.props["avatar_real_id"]?.double.map { Int64($0) }
        }
        .task(id: reload) { await load() }
    }

    // ---------------------------------------------------------------- load ----

    private func load() async {
        loading = true
        catalog = ((try? await Smartico.api.getAvatarsList()) ?? [])
            // hidden-until-earned avatars stay out of the grid entirely
            .filter { $0.hide_until_achieved != true || $0.is_given == true }
            .sorted { ($0.priority ?? 0) < ($1.priority ?? 0) }
        customized = ((try? await Smartico.api.getAvatarsCustomized()) ?? [])
            .sorted { ($0.dt_created ?? 0) > ($1.dt_created ?? 0) }
        prompts = (try? await Smartico.api.getAvatarPrompts()) ?? []
        if promptId == nil { promptId = prompts.first?.prompt_id }
        loading = false
        demoLog("avatars: catalog=\(catalog.count) customized=\(customized.count) prompts=\(prompts.count) active=\(activeRealId.map { String($0) } ?? "nil")")
    }

    private func apply(_ url: String, _ realId: Int64) {
        Task {
            demoLog("setAvatar(avatar_url: \(url), avatar_real_id: \(realId)) → sending")
            var r: TSetAvatarResult?
            do {
                r = try await Smartico.api.setAvatar(avatar_url: url, avatar_real_id: realId)
                demoLog("setAvatar ← err_code=\(r?.err_code.map { String($0) } ?? "nil") err_message=\(r?.err_message ?? "nil")")
            } catch {
                demoLog("setAvatar failed: \(error)")
            }
            if let r = r {
                if r.err_code == 0 {
                    activeRealId = realId
                    Sdk.shared.onAvatarApplied(url) // show it immediately, everywhere
                    note = "Applied ✓"
                } else {
                    note = r.err_message ?? "Failed to apply (code \(r.err_code.map { String($0) } ?? "null"))"
                }
            } else {
                note = "Failed to apply"
            }
            reload += 1
        }
    }

    // What the AI styles a new avatar from: the active one, else the first free
    // one, else whatever is first in the catalog.
    private var base: TAvatarDefinition? {
        catalog.first { $0.avatar_real_id == activeRealId }
            ?? catalog.first { $0.avatar_source_type_id == 0 }
            ?? catalog.first
    }

    // ------------------------------------------------------------- catalog ----

    private var catalogCard: some View {
        Card {
            Title("Catalog (\(catalog.count))")
            Meta("🔒 avatars unlock through levels and missions")
            LazyVGrid(columns: grid, alignment: .leading, spacing: 8) {
                ForEach(Array(catalog.enumerated()), id: \.offset) { _, a in
                    // Locked = not granted to this user and not a free
                    // (source type 0) avatar. Shown dimmed with a padlock
                    // instead of looking selectable and failing on tap.
                    let locked = a.is_given != true && a.avatar_source_type_id != 0
                    let active = a.avatar_real_id == activeRealId || a.is_in_use == true
                    Button {
                        // avatar_url is the absolute CDN link; `url` is the raw
                        // relative path the server does not accept here
                        apply(a.avatar_url ?? "", a.avatar_real_id ?? 0)
                    } label: {
                        AvatarTile(url: a.avatar_url, locked: locked, active: active)
                    }
                    .disabled(locked)
                    .accessibilityIdentifier("avatar-\(a.avatar_real_id ?? 0)")
                }
            }
            .padding(.top, 8)
        }
    }

    // ------------------------------------------------------------------ AI ----

    private var aiCard: some View {
        Card {
            Title("Customize with AI")
            if let base = base {
                HStack(spacing: 10) {
                    RemoteImage(url: sdk.avatar ?? base.avatar_url)
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    Meta("Styling your current avatar")
                }
                .padding(.top, 6)
                if prompts.isEmpty {
                    Meta("No AI styles configured on this label.").padding(.top, 8)
                } else {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                        ForEach(Array(prompts.enumerated()), id: \.offset) { _, p in
                            let on = p.prompt_id == promptId
                            Button { promptId = p.prompt_id } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(stripHtml(p.name))
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(.white)
                                        .lineLimit(1)
                                    Text((p.cost_value ?? 0) > 0 ? "\(currencyIcon(p.cost_currency_type_id))\(Int(p.cost_value ?? 0))" : "free")
                                        .font(.system(size: 11))
                                        .foregroundColor(on ? .white : .gold)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(on ? Color.accent : Color.bg)
                                .clipShape(RoundedRectangle(cornerRadius: 9))
                            }
                        }
                    }
                    .padding(.top, 8)

                    ActionButton(label: generating ? "Generating… (5–20s)" : "Generate", onResult: { _ in }) {
                        await generate(from: base)
                    }
                    .padding(.top, 8)
                    if let genNote = genNote { Meta(genNote).padding(.top, 6) }
                    if let g = generated {
                        HStack(spacing: 10) {
                            RemoteImage(url: g.url)
                                .frame(width: 64, height: 64)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            ActionButton(label: "Apply this") { apply(g.url, g.realId); return "" }
                        }
                        .padding(.top, 8)
                    }
                }
            } else {
                Meta("No avatar to style yet.")
            }
        }
    }

    /**
     * AI generation — an HTTP POST that spends the prompt's price from the
     * user's balance. Wired exactly like the Kotlin demo; the D2 live check
     * does not press it.
     */
    private func generate(from base: TAvatarDefinition) async -> String {
        let userId = sdk.props["user_id"]?.double.map { Int64($0) }
        guard let userId = userId, let pid = promptId else { return "Not ready yet" }
        generating = true
        generated = nil
        genNote = nil
        demoLog("avatarsCustomize(userId: \(userId), promptId: \(pid), avatarRealId: \(base.avatar_real_id ?? 0)) → sending")
        let r = try? await Smartico.api.avatarsCustomize(
            userId: userId,
            promptId: pid,
            avatarUrl: base.avatar_url ?? "",
            avatarRealId: base.avatar_real_id ?? 0
        )
        generating = false
        // Success is a cdn_url — this endpoint reports failures through
        // errCode/errMessage, which is why a plain "err_code == 0" check
        // printed "Failed (null)".
        let url = r?.cdn_url
        let code = r?.errCode?.double.map { Int($0) }
        demoLog("avatarsCustomize ← cdn_url=\(url ?? "nil") errCode=\(code.map { String($0) } ?? "nil")")
        if let url = url, !url.isEmpty {
            generated = GeneratedAvatar(url: url, realId: base.avatar_real_id ?? 0)
            reload += 1
            genNote = "Generated ✓ — apply it below"
        } else if code == 12001 {
            genNote = "Monthly limit reached for your custom avatars."
        } else if code == 12002 {
            genNote = "Custom avatars unavailable right now — try later."
        } else {
            genNote = r?.errMessage ?? "Generation failed (maybe not enough balance)."
        }
        return genNote ?? ""
    }

    // ---------------------------------------------------------- customized ----

    private var customizedCard: some View {
        Card {
            Title("Your AI avatars (\(customized.count))")
            LazyVGrid(columns: grid, alignment: .leading, spacing: 8) {
                ForEach(Array(customized.enumerated()), id: \.offset) { _, c in
                    Button {
                        apply(c.url ?? "", c.avatar_real_id ?? 0)
                    } label: {
                        RemoteImage(url: c.url)
                            .frame(width: 64, height: 64)
                            .background(Color.bg)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            .padding(.top, 8)
        }
    }
}

private struct GeneratedAvatar {
    let url: String
    let realId: Int64
}

private struct AvatarTile: View {
    let url: String?
    let locked: Bool
    let active: Bool

    var body: some View {
        ZStack {
            RemoteImage(url: url).opacity(locked ? 0.3 : 1)
            if locked {
                Text("🔒").font(.system(size: 16))
            }
            if active {
                Text("✓")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.accent)
                    .padding(3)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
        }
        .frame(width: 64, height: 64)
        .background(Color.bg)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(active ? Color.accent : Color.clear, lineWidth: 2))
    }
}

/** Fills its frame with the image (Thumb fits; avatars want to fill the tile). */
private struct RemoteImage: View {
    let url: String?

    var body: some View {
        if let url = url, let u = URL(string: url) {
            AsyncImage(url: u) { $0.resizable().scaledToFill() } placeholder: { Color.clear }
        } else {
            Color.clear
        }
    }
}

/** cost_currency_type_id → icon (0 points, 1 gems, 2 diamonds). */
private func currencyIcon(_ id: Int64?) -> String {
    switch id ?? 0 {
    case 1: return "💎"
    case 2: return "🔷"
    default: return "🪙"
    }
}
