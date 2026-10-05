import Foundation
import SmarticoPublicAPI

/**
 * The demo's data mirror for achievement-driven lists, built the same way as
 * the RN demo's store.
 *
 * ONE place fetches; every screen reads the same published value. That matters
 * because missions show up in four places at once (tab, lobby carousel, in-game
 * panel, badges): with per-screen loads a single server push meant four
 * identical requests, and each screen dropped its list to a spinner while
 * refetching. Here a push costs one request and the previous data stays on
 * screen until the new list lands.
 */
@MainActor
final class Store: ObservableObject {
    static let shared = Store()

    /** Guards against stacking identical requests (RN: the `inFlight` set). */
    private var inFlight = Set<String>()

    @Published private(set) var missions: [TMissionOrBadge] = []
    @Published private(set) var badges: [TMissionOrBadge] = []
    @Published private(set) var tournaments: [TTournament] = []

    /** Flips once the first load lands, so screens can tell empty from loading. */
    @Published private(set) var loaded = false

    private init() {}

    func refreshAll() {
        refreshMissions()
        refreshBadges()
        refreshTournaments()
    }

    func refreshMissions() {
        load("missions") {
            let list = try await Smartico.api.getMissions()
            self.missions = list
            self.loaded = true
            demoLog("missions loaded: \(list.count)")
        }
    }

    func refreshBadges() {
        load("badges") {
            // 1128 is the demo label's hidden section
            self.badges = try await Smartico.api.getBadges().filter { $0.custom_section_id != 1128 }
        }
    }

    func refreshTournaments() {
        load("tournaments") {
            // Tournaments flagged only_in_custom_section belong to that section's own
            // view — keeping them here would also skew the per-tab counters.
            self.tournaments = try await Smartico.api.getTournamentsList().filter { $0.only_in_custom_section != true }
        }
    }

    /** User boundary: a different player must not see the old lists. */
    func clear() {
        missions = []
        badges = []
        tournaments = []
        loaded = false
    }

    private func load(_ key: String, _ block: @escaping @MainActor () async throws -> Void) {
        if inFlight.contains(key) { return }
        inFlight.insert(key)
        Task { @MainActor in
            defer { self.inFlight.remove(key) }
            do {
                try await block()
            } catch {
                demoLog("\(key) refresh failed: \(error.localizedDescription)")
            }
        }
    }
}
