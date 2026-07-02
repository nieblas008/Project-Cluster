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
    private(set) var deskState = DeskState()
    private(set) var raceState = RaceState()
    private(set) var lastLapMs: UInt32?
    private(set) var bestLapMs: UInt32?
    var inWorld = false

    let voice = VoiceController()
    weak var scene: WorldScene? {
        didSet { voice.onSpeakingChanged = { [weak self] ids in self?.scene?.setSpeaking(ids) } }
    }
    private var session: HostSession?
    private var eventsTask: Task<Void, Never>?
    /// Keeps the Mac awake while the world is up (Phase 7). Display may sleep;
    /// the system may not — the room's uptime is this process's uptime.
    private var sleepActivity: NSObjectProtocol?

    func startVoice(localWireID: UInt64, pushToTalk: Bool, status: PlayerStatus) {
        let session = session
        voice.start(localWireID: localWireID, pushToTalk: pushToTalk) { seq, opus in
            await session?.sendHostVoice(seq: seq, opus: opus)
        }
        voice.applyStatus(status)
    }

    func setStatus(_ status: PlayerStatus) {
        voice.applyStatus(status)
        let session = session
        Task { await session?.setLocalStatus(status) }
    }

    func performDesk(_ command: DeskCommand) {
        let session = session
        Task { await session?.performDeskCommand(command) }
    }

    func performRace(_ command: RaceCommand) {
        let session = session
        Task { await session?.performRaceCommand(command) }
    }

    func start(
        endpoint: RelayEndpoint, identity: PlayerIdentity, displayName: String,
        avatarPreset: String, map: WorldMap, allowUDP: Bool, status: PlayerStatus
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
                    allowUDP: allowUDP,
                    initialStatus: status,
                    deskStore: WorldDeskStoreAdapter(database: database),
                    lapStore: WorldLapStoreAdapter(database: database)
                )
                self.session = session
                self.consumeEvents(of: session)
                let code = try await session.start()
                self.state = .hosting(code: code)
                self.sleepActivity = ProcessInfo.processInfo.beginActivity(
                    options: [.idleSystemSleepDisabled, .automaticTerminationDisabled],
                    reason: "Hosting a Project Cluster session")
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
                    self.voice.updateProximity(snapshot: snapshot)
                case .voiceReceived(let speakerID, let seq, let opus):
                    self.voice.receive(speakerID: speakerID, seq: seq, opus: opus)
                case .deskStateChanged(let deskState):
                    self.deskState = deskState
                    self.scene?.applyDeskState(deskState)
                case .raceStateChanged(let raceState):
                    self.raceState = raceState
                    self.scene?.applyRaceState(raceState)
                case .lapCompleted(let timeMs, let isBest):
                    self.lastLapMs = timeMs
                    if isBest || self.bestLapMs.map({ timeMs < $0 }) ?? true {
                        self.bestLapMs = timeMs
                    }
                case .horn(let from):
                    self.scene?.playHorn(from: from)
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

    func kick(playerID: String, block: Bool) {
        let session = session
        Task { await session?.kick(playerID: playerID, block: block) }
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
        deskState = DeskState()
        raceState = RaceState()
        lastLapMs = nil
        bestLapMs = nil
        inWorld = false
        voice.stop()
        if let activity = sleepActivity {
            ProcessInfo.processInfo.endActivity(activity)
            sleepActivity = nil
        }
    }
}

extension HostLobbyModel: WorldSceneDelegate {
    /// Host's own avatar: published straight into the authoritative world.
    func worldScene(
        _ scene: WorldScene, didUpdateLocal position: Vec2, facing: Facing,
        isMoving: Bool, input: MoveInput, heading: Double, isKarted: Bool, drifting: Bool
    ) {
        let session = session
        Task {
            await session?.updateLocalPlayer(
                position: position, facing: facing, isMoving: isMoving,
                heading: heading, drifting: drifting)
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
    private(set) var deskState = DeskState()
    private(set) var raceState = RaceState()
    private(set) var lastLapMs: UInt32?
    private(set) var bestLapMs: UInt32?

    let voice = VoiceController()
    weak var scene: WorldScene? {
        didSet { voice.onSpeakingChanged = { [weak self] ids in self?.scene?.setSpeaking(ids) } }
    }
    private var session: JoinSession?
    private var eventsTask: Task<Void, Never>?
    private var inputSeq: UInt32 = 0

    func startVoice(localWireID: UInt64, pushToTalk: Bool, status: PlayerStatus) {
        let session = session
        voice.start(localWireID: localWireID, pushToTalk: pushToTalk) { seq, opus in
            await session?.sendVoice(seq: seq, opus: opus)
        }
        voice.applyStatus(status)
    }

    func setStatus(_ status: PlayerStatus) {
        voice.applyStatus(status)
        let session = session
        Task { await session?.setStatus(status) }
    }

    func performDesk(_ command: DeskCommand) {
        let session = session
        Task { await session?.sendDeskCommand(command) }
    }

    func performRace(_ command: RaceCommand) {
        let session = session
        Task { await session?.sendRaceCommand(command) }
    }

    func join(
        code: String, endpoint: RelayEndpoint, identity: PlayerIdentity, displayName: String,
        avatarPreset: String, mapHash: String, preferUDP: Bool, status: PlayerStatus
    ) {
        guard case .idle = state else { return }
        state = .connecting(status: "Connecting…")
        usingUDP = nil
        let session = JoinSession(
            endpoint: endpoint, identity: identity,
            displayName: displayName, avatarPreset: avatarPreset,
            mapHash: mapHash, preferUDP: preferUDP, initialStatus: status)
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
                    self.voice.updateProximity(snapshot: snapshot)
                case .voiceReceived(let speakerID, let seq, let opus):
                    self.voice.receive(speakerID: speakerID, seq: seq, opus: opus)
                case .deskState(let deskState):
                    self.deskState = deskState
                    self.scene?.applyDeskState(deskState)
                case .raceState(let raceState):
                    self.raceState = raceState
                    self.scene?.applyRaceState(raceState)
                case .lapCompleted(let timeMs, let isBest):
                    self.lastLapMs = timeMs
                    if isBest || self.bestLapMs.map({ timeMs < $0 }) ?? true {
                        self.bestLapMs = timeMs
                    }
                case .horn(let from):
                    self.scene?.playHorn(from: from)
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
        deskState = DeskState()
        raceState = RaceState()
        lastLapMs = nil
        bestLapMs = nil
        voice.stop()
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
        isMoving: Bool, input: MoveInput, heading: Double, isKarted: Bool, drifting: Bool
    ) {
        inputSeq &+= 1
        let frame = InputFrame(
            seq: inputSeq, input: input, x: Float(position.x), y: Float(position.y),
            flags: drifting ? InputFlags.drift : 0, heading: Float(heading))
        let session = session
        Task { await session?.sendInput(frame) }
    }
}
