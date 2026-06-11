import ClusterNet
import ClusterServer
import Foundation
import Observation

/// App-level state: the device identity, the current screen, and the Phase 0
/// host-world bootstrap. Networking state joins in Phase 1.
@MainActor
@Observable
final class AppModel {
    enum Route {
        case welcome
        case host
        case join
    }

    var route: Route = .welcome

    private(set) var identity: PlayerIdentity?
    private(set) var identityError: String?

    var displayName: String {
        didSet { UserDefaults.standard.set(displayName, forKey: "displayName") }
    }

    // MARK: Host-world bootstrap (Phase 0 scope)

    private(set) var worldSummary: [String] = []
    private(set) var worldError: String?

    init(secretStore: SecretStore = KeychainSecretStore()) {
        self.displayName = UserDefaults.standard.string(forKey: "displayName") ?? ""
        do {
            self.identity = try IdentityManager.loadOrCreate(store: secretStore)
        } catch {
            self.identityError = "Could not load identity: \(error)"
        }
    }

    var hasUsableProfile: Bool {
        identity != nil && !displayName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Creates (or opens) the world database and surfaces what's inside it —
    /// the Phase 0 proof that hosting stores everything on this Mac.
    func prepareWorld() {
        worldError = nil
        worldSummary = []
        do {
            let url = try WorldDatabase.defaultFileURL()
            let db = try WorldDatabase(fileURL: url)
            let space = try db.ensureSpace(named: "The Mansion")
            let players = try db.playerCount()
            worldSummary = [
                "Space: \(space.name)",
                "Invite secret: \(space.inviteSecret)",
                "Known players: \(players)",
                "Stored at: \(url.path)",
            ]
        } catch {
            worldError = "World storage failed: \(error)"
        }
    }
}
