import ClusterNet
import ClusterProtocol
import ClusterServer
import Foundation
import Observation

/// UI-facing mirror of a HostSession actor's events.
@MainActor
@Observable
final class HostLobbyModel {
    enum State: Equatable {
        case idle
        case starting
        case hosting(code: String)
    }

    struct Knock: Identifiable, Equatable {
        var id: String  // playerID
        var displayName: String
    }

    private(set) var state: State = .idle
    private(set) var roster: [RosterEntry] = []
    private(set) var knocks: [Knock] = []
    private(set) var errorMessage: String?
    var inWorld = false

    weak var scene: WorldScene?
    private var session: HostSession?
    private var eventsTask: Task<Void, Never>?

    func start(
        endpoint: RelayEndpoint, identity: PlayerIdentity, displayName: String,
        avatarPreset: String, map: WorldMap, allowUDP: Bool
    ) {
        guard state == .idle else { return }
        state = .starting
        errorMessage = nil
        Task {
            do {
                let database = try WorldDatabase(fileURL: WorldDatabase.defaultFileURL())
                let space = try database.ensureSpace(named: "The Mansion")
                let session = HostSession(
                    endpoint: endpoint,
                    identity: identity,
                    directory: WorldDirectoryAdapter(database: database),
                    spaceName: space.name,
                    hostDisplayName: displayName,
                    hostAvatarPreset: avatarPreset,
                    map: map,
                    allowUDP: allowUDP
                )
                self.session = session
                self.consumeEvents(of: session)
                let code = try await session.start()
                self.state = .hosting(code: code)
            } catch {
                self.errorMessage = "Could not start hosting: \(error.localizedDescription)"
                self.state = .idle
            }
        }
    }

    private func consumeEvents(of session: HostSession) {
        eventsTask = Task {
            for await event in session.events {
                switch event {
                case .registered(let code):
                    self.state = .hosting(code: code)
                case .knock(let playerID, let displayName):
                    self.knocks.append(Knock(id: playerID, displayName: displayName))
                case .rosterChanged(let roster):
                    self.roster = roster
                    self.scene?.applyRoster(roster)
                case .worldSnapshot(let snapshot):
                    self.scene?.applySnapshot(snapshot)
                case .ended(let reason):
                    if self.state != .idle {
                        self.errorMessage = reason
                    }
                    self.reset()
                }
            }
        }
    }

    func resolveKnock(_ knock: Knock, approve: Bool) {
        knocks.removeAll { $0.id == knock.id }
        let session = session
        Task { await session?.resolveKnock(playerID: knock.id, approve: approve) }
    }

    func stop() {
        let session = session
        self.session = nil
        eventsTask?.cancel()
        eventsTask = nil
        reset()
        Task { await session?.stop() }
    }

    private func reset() {
        state = .idle
        roster = []
        knocks = []
        inWorld = false
    }
}

extension HostLobbyModel: WorldSceneDelegate {
    /// Host's own avatar: published straight into the authoritative world.
    func worldScene(
        _ scene: WorldScene, didUpdateLocal position: Vec2, facing: Facing,
        isMoving: Bool, input: MoveInput
    ) {
        let session = session
        Task {
            await session?.updateLocalPlayer(position: position, facing: facing, isMoving: isMoving)
        }
    }
}

/// UI-facing mirror of a JoinSession actor's events.
@MainActor
@Observable
final class JoinLobbyModel {
    enum State: Equatable {
        case idle
        case connecting(status: String)
        case knocking
        case joined(spaceName: String)
        case denied(reason: String)
    }

    private(set) var state: State = .idle
    private(set) var roster: [RosterEntry] = []
    private(set) var usingUDP: Bool?

    weak var scene: WorldScene?
    private var session: JoinSession?
    private var eventsTask: Task<Void, Never>?
    private var inputSeq: UInt32 = 0

    func join(
        code: String, endpoint: RelayEndpoint, identity: PlayerIdentity, displayName: String,
        avatarPreset: String, mapHash: String, preferUDP: Bool
    ) {
        guard case .idle = state else { return }
        state = .connecting(status: "Connecting…")
        usingUDP = nil
        let session = JoinSession(
            endpoint: endpoint, identity: identity,
            displayName: displayName, avatarPreset: avatarPreset,
            mapHash: mapHash, preferUDP: preferUDP)
        self.session = session
        eventsTask = Task {
            for await event in session.events {
                switch event {
                case .status(let status):
                    if case .connecting = self.state {
                        self.state = .connecting(status: status)
                    }
                case .knockPending:
                    self.state = .knocking
                case .welcomed(let spaceName, let roster):
                    self.state = .joined(spaceName: spaceName)
                    self.roster = roster
                case .rosterChanged(let roster):
                    self.roster = roster
                    self.scene?.applyRoster(roster)
                case .transport(let udp):
                    self.usingUDP = udp
                case .worldSnapshot(let snapshot):
                    self.scene?.applySnapshot(snapshot)
                case .denied(let reason):
                    self.state = .denied(reason: reason)
                    self.roster = []
                case .ended(let reason):
                    switch self.state {
                    case .idle, .denied:
                        break  // already reset / keep the specific denial
                    default:
                        self.state = .denied(reason: reason)
                    }
                    self.roster = []
                }
            }
        }
        Task { await session.start(code: code) }
    }

    func leave() {
        let session = session
        self.session = nil
        eventsTask?.cancel()
        eventsTask = nil
        state = .idle
        roster = []
        usingUDP = nil
        Task { await session?.leave() }
    }

    func reset() {
        leave()
    }
}

extension JoinLobbyModel: WorldSceneDelegate {
    /// Joiner's avatar: predicted locally, sent as input for host validation.
    func worldScene(
        _ scene: WorldScene, didUpdateLocal position: Vec2, facing: Facing,
        isMoving: Bool, input: MoveInput
    ) {
        inputSeq &+= 1
        let frame = InputFrame(
            seq: inputSeq, input: input, x: Float(position.x), y: Float(position.y))
        let session = session
        Task { await session?.sendInput(frame) }
    }
}
