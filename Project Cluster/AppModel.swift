import ClusterNet
import ClusterProtocol
import ClusterServer
import Foundation
import Observation

/// App-level state: identity, profile, relay configuration, current screen,
/// and the live host/join lobby models.
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

    static let avatarPresets = ["default", "sky", "mint", "coral", "violet"]

    var displayName: String {
        didSet { UserDefaults.standard.set(displayName, forKey: "displayName") }
    }
    var avatarPreset: String {
        didSet { UserDefaults.standard.set(avatarPreset, forKey: "avatarPreset") }
    }

    // MARK: Relay configuration (Settings)

    var relayHost: String {
        didSet { UserDefaults.standard.set(relayHost, forKey: "relayHost") }
    }
    var relayControlPort: String {
        didSet { UserDefaults.standard.set(relayControlPort, forKey: "relayControlPort") }
    }
    var relayUDPPort: String {
        didSet { UserDefaults.standard.set(relayUDPPort, forKey: "relayUDPPort") }
    }
    var relayFingerprint: String {
        didSet { UserDefaults.standard.set(relayFingerprint, forKey: "relayFingerprint") }
    }

    var relayEndpoint: RelayEndpoint {
        RelayEndpoint(
            host: relayHost.trimmingCharacters(in: .whitespaces),
            controlPort: UInt16(relayControlPort) ?? 7600,
            udpPort: UInt16(relayUDPPort) ?? 7601,
            certFingerprint: relayFingerprint
        )
    }

    /// "auto" (probe UDP, fall back) or "tcp" (compatibility) — ADR 0002.
    var transportMode: String {
        didSet { UserDefaults.standard.set(transportMode, forKey: "transportMode") }
    }
    var preferUDP: Bool { transportMode != "tcp" }

    /// The bundled mansion, loaded once.
    private(set) var worldMap: WorldMap?
    private(set) var worldMapError: String?

    var showSettings = false
    private(set) var doctorChecks: [DoctorCheck] = []
    private(set) var doctorRunning = false

    // MARK: Lobby models

    let hostLobby = HostLobbyModel()
    let joinLobby = JoinLobbyModel()

    var hasUsableProfile: Bool {
        identity != nil && !displayName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    init(secretStore: SecretStore = KeychainSecretStore()) {
        let defaults = UserDefaults.standard
        self.displayName = defaults.string(forKey: "displayName") ?? ""
        self.avatarPreset = defaults.string(forKey: "avatarPreset") ?? "default"
        self.relayHost = defaults.string(forKey: "relayHost") ?? ""
        self.relayControlPort = defaults.string(forKey: "relayControlPort") ?? "7600"
        self.relayUDPPort = defaults.string(forKey: "relayUDPPort") ?? "7601"
        self.relayFingerprint = defaults.string(forKey: "relayFingerprint") ?? ""
        self.transportMode = defaults.string(forKey: "transportMode") ?? "auto"
        if let url = Bundle.main.url(forResource: "mansion", withExtension: "json") {
            do {
                self.worldMap = try TiledMapLoader.load(data: try Data(contentsOf: url))
            } catch {
                self.worldMapError = "Bundled map failed to load: \(error)"
            }
        } else {
            self.worldMapError = "mansion.json missing from the app bundle"
        }
        do {
            self.identity = try IdentityManager.loadOrCreate(store: secretStore)
        } catch {
            self.identityError = "Could not load identity: \(error)"
        }
    }

    func runDoctor() {
        doctorRunning = true
        doctorChecks = []
        let endpoint = relayEndpoint
        Task {
            let checks = await ConnectivityDoctor.run(endpoint: endpoint)
            self.doctorChecks = checks
            self.doctorRunning = false
        }
    }
}
