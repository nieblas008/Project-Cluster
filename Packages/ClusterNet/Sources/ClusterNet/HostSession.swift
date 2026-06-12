import ClusterProtocol
import CryptoKit
import Foundation

public enum HostSessionEvent: Sendable {
    case registered(code: String)
    /// A never-seen identity wants in; answer via `resolveKnock`.
    case knock(playerID: String, displayName: String)
    case rosterChanged([RosterEntry])
    /// The 15 Hz world state — the host's own scene renders from this too.
    case worldSnapshot(WorldSnapshot)
    /// A speaker audible from the host's position — feed the host's playback.
    case voiceReceived(speakerID: UInt64, seq: UInt32, opus: Data)
    case ended(reason: String)
}

/// The hosting side: relay registration, attach connections, responder
/// handshake, entry gating (Phase 1) — plus the authoritative world: spawn,
/// input validation, 15 Hz snapshot fan-out over each member's chosen
/// transport (Phase 2, ADR 0002).
public actor HostSession {
    public nonisolated let events: AsyncStream<HostSessionEvent>
    private let eventsContinuation: AsyncStream<HostSessionEvent>.Continuation

    private let endpoint: RelayEndpoint
    private let identity: PlayerIdentity
    private let directory: any HostDirectory
    private let spaceName: String
    private let hostDisplayName: String
    private let hostAvatarPreset: String
    private let map: WorldMap
    /// Session-wide policy from Settings → Connection (ADR 0002).
    private let allowUDP: Bool
    private let sessionKey = HostSessionKey()

    private var control: FrameConnection?
    private var sessionCode: String?

    private struct Member {
        var entry: RosterEntry
        var tunnel: FrameConnection
        var sendCipher: SecureChannelCipher
        var datagram: DatagramChannel?
        /// Set by the joiner's transportSelected; sending honors it only when
        /// the host-side datagram channel actually bound.
        var wantsUDP = false
    }

    private struct WorldPlayer {
        var position: Vec2
        var facing: Facing = .down
        var isMoving = false
        var lastInputAt: ContinuousClock.Instant?
    }

    private var members: [String: Member] = [:]
    private var world: [String: WorldPlayer] = [:]
    private var tick: UInt32 = 0
    private var knockDecisions: [String: CheckedContinuation<Bool, Never>] = [:]
    private var tasks: [Task<Void, Never>] = []

    public init(
        endpoint: RelayEndpoint,
        identity: PlayerIdentity,
        directory: any HostDirectory,
        spaceName: String,
        hostDisplayName: String,
        hostAvatarPreset: String,
        map: WorldMap,
        allowUDP: Bool
    ) {
        self.endpoint = endpoint
        self.identity = identity
        self.directory = directory
        self.spaceName = spaceName
        self.hostDisplayName = hostDisplayName
        self.hostAvatarPreset = hostAvatarPreset
        self.map = map
        self.allowUDP = allowUDP
        (events, eventsContinuation) = AsyncStream.makeStream()
    }

    // MARK: Lifecycle

    /// Connects, registers, spawns the host avatar, starts the tick loop, and
    /// returns the session code.
    @discardableResult
    public func start() async throws -> String {
        let control = FrameConnection(endpoint: endpoint)
        self.control = control
        try await control.start()
        try await control.send(.clientHello(wireVersion: ProtocolInfo.wireVersion, role: .host))
        try await control.send(
            .registerHost(sessionPublicKey: sessionKey.publicKeyData, spaceName: spaceName))

        let code: String = try await withCheckedThrowingContinuation { cont in
            tasks.append(
                Task { [weak self] in
                    await self?.runControlLoop(control: control, registration: cont)
                })
        }
        sessionCode = code
        world[identity.playerID] = WorldPlayer(position: spawnPosition())
        eventsContinuation.yield(.registered(code: code))
        eventsContinuation.yield(.rosterChanged(currentRoster()))
        startPings(on: control)
        startTickLoop()
        return code
    }

    public func stop() async {
        for task in tasks { task.cancel() }
        for member in members.values {
            await member.datagram?.cancel()
            await member.tunnel.cancel()
        }
        await control?.cancel()
        members.removeAll()
        world.removeAll()
        eventsContinuation.yield(.ended(reason: "Hosting stopped."))
        eventsContinuation.finish()
    }

    /// UI's answer to a `.knock` event.
    public func resolveKnock(playerID: String, approve: Bool) {
        knockDecisions.removeValue(forKey: playerID)?.resume(returning: approve)
    }

    /// The host's own avatar, reported by its scene (~30 Hz). The host is the
    /// authority; its own movement isn't validated, just published.
    public func updateLocalPlayer(position: Vec2, facing: Facing, isMoving: Bool) {
        world[identity.playerID] = WorldPlayer(
            position: position, facing: facing, isMoving: isMoving, lastInputAt: nil)
    }

    private func spawnPosition() -> Vec2 {
        map.spawnPoints.randomElement() ?? Vec2(x: 2, y: 2)
    }

    // MARK: Control loop

    private func runControlLoop(
        control: FrameConnection, registration: CheckedContinuation<String, Error>
    ) async {
        var registrationPending: CheckedContinuation<String, Error>? = registration
        do {
            for try await frame in control.incomingFrames {
                switch try ControlMessage(decoding: frame) {
                case .registerAck(let code):
                    registrationPending?.resume(returning: code)
                    registrationPending = nil
                case .incomingPair(let pairID):
                    tasks.append(
                        Task { [weak self] in
                            await self?.serveIncomingPair(pairID: pairID)
                        })
                case .peerGone, .pong:
                    break
                case .error(let message):
                    throw ConnectionError.failed(message)
                default:
                    throw ConnectionError.protocolViolation
                }
            }
            throw ConnectionError.closed
        } catch {
            registrationPending?.resume(throwing: error)
            eventsContinuation.yield(.ended(reason: "Relay connection lost."))
        }
    }

    private func startPings(on control: FrameConnection) {
        tasks.append(
            Task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(20))
                    try? await control.send(.ping(nonce: UInt64.random(in: 0...UInt64.max)))
                }
            })
    }

    // MARK: World tick (PLAN §7)

    private func startTickLoop() {
        tasks.append(
            Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(66))  // ~15 Hz
                    await self?.broadcastTick()
                }
            })
    }

    private func broadcastTick() async {
        tick &+= 1
        let players = world.map { id, player in
            PlayerSnapshot(
                id: PlayerWireID.prefix(fromHexID: id),
                x: Float(player.position.x), y: Float(player.position.y),
                facing: player.facing, isMoving: player.isMoving)
        }
        let snapshot = WorldSnapshot(tick: tick, players: players)
        eventsContinuation.yield(.worldSnapshot(snapshot))

        guard !members.isEmpty, let bytes = try? WorldPayload.snapshot(snapshot).encoded() else {
            return
        }
        for (playerID, member) in members {
            if member.wantsUDP, let datagram = member.datagram {
                await datagram.send(bytes)
            } else {
                try? await sendMessage(.worldFrame(payload: Data(bytes)), to: playerID)
            }
        }
    }

    private func applyInput(playerID: String, frame: InputFrame) {
        guard var player = world[playerID] else { return }
        let now = ContinuousClock.now
        let dt: Double
        if let last = player.lastInputAt {
            let elapsed = (now - last).components
            dt = max(
                Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18, 1.0 / 60)
        } else {
            dt = 1.0 / 15
        }
        player.position = MovementSim.validate(
            previous: player.position,
            proposed: Vec2(x: Double(frame.x), y: Double(frame.y)),
            dt: dt,
            collision: map.collision
        )
        player.facing = Facing.from(input: frame.input, previous: player.facing)
        player.isMoving = frame.input.isMoving
        player.lastInputAt = now
        world[playerID] = player
    }

    // MARK: Serving a joiner

    private func serveIncomingPair(pairID: UInt32) async {
        let tunnel = FrameConnection(endpoint: endpoint)
        var admittedPlayerID: String?
        do {
            try await tunnel.start()
            try await tunnel.send(.clientHello(wireVersion: ProtocolInfo.wireVersion, role: .attach))
            try await tunnel.send(.attach(pairID: pairID))

            var frames = tunnel.incomingFrames.makeAsyncIterator()

            // Control tail: dataPlane (flow credentials), then spliceBegin.
            var flowInfo: (flowID: UInt32, token: UInt64)?
            preSplice: while let frame = try await frames.next() {
                switch try ControlMessage(decoding: frame) {
                case .dataPlane(let flowID, let token):
                    flowInfo = (flowID, token)
                case .spliceBegin:
                    break preSplice
                default:
                    throw ConnectionError.protocolViolation
                }
            }

            // Responder handshake: one frame in, one frame out, keys ready.
            guard let message1 = try await frames.next() else { throw ConnectionError.closed }
            let (keys, message2) = try SessionHandshake.respond(hostKey: sessionKey, message1: message1)
            try await tunnel.send(frame: message2)
            var receiveCipher = SecureChannelCipher(key: keys.receiveKey)
            var sendCipher = SecureChannelCipher(key: keys.sendKey)

            // First sealed message must be the introduction.
            guard let helloFrame = try await frames.next() else { throw ConnectionError.closed }
            guard
                case .joinHello(let identityKey, let displayName, let avatarPreset, let inviteSecret, let signature) =
                    try SessionMessage(decoding: receiveCipher.open(helloFrame))
            else { throw ConnectionError.protocolViolation }

            let playerID = identityKey.map { String(format: "%02x", $0) }.joined()

            // Gate 1: the identity must prove it owns its key, bound to THIS tunnel.
            guard
                JoinSignature.verify(
                    signature: signature, identityKey: identityKey,
                    transcriptHash: keys.transcriptHash),
                inviteSecret.uppercased() == (sessionCode ?? "")
            else {
                let sealed = try sendCipher.seal(
                    SessionMessage.denied(reason: "Join verification failed.").encoded())
                try await tunnel.send(frame: sealed)
                await tunnel.cancel()
                return
            }

            // Gate 2: blocklist / knock.
            let known = try directory.knownPlayer(id: playerID)
            if known?.isBlocked == true {
                let sealed = try sendCipher.seal(
                    SessionMessage.denied(reason: "You are blocked from this space.").encoded())
                try await tunnel.send(frame: sealed)
                await tunnel.cancel()
                return
            }
            if known?.isApproved != true && !directory.autoApprovesUnknownPlayers {
                let sealed = try sendCipher.seal(SessionMessage.knockPending.encoded())
                try await tunnel.send(frame: sealed)
                eventsContinuation.yield(.knock(playerID: playerID, displayName: displayName))
                let approved = await withCheckedContinuation { cont in
                    knockDecisions[playerID] = cont
                }
                guard approved else {
                    let sealed = try sendCipher.seal(
                        SessionMessage.denied(reason: "The host declined your knock.").encoded())
                    try await tunnel.send(frame: sealed)
                    await tunnel.cancel()
                    return
                }
            }

            // Admitted. The send cipher's ownership moves into the member —
            // the local copy must never seal again or counters fork.
            try directory.recordJoin(id: playerID, displayName: displayName, avatarPreset: avatarPreset)
            admittedPlayerID = playerID
            members[playerID] = Member(
                entry: RosterEntry(
                    playerID: playerID, displayName: displayName,
                    avatarPreset: avatarPreset, isOnline: true),
                tunnel: tunnel,
                sendCipher: sendCipher
            )
            world[playerID] = WorldPlayer(position: spawnPosition())

            // Host side of the datagram plane: bind regardless of the joiner's
            // eventual choice — it's their call which road they use (ADR 0002).
            if allowUDP, let flow = flowInfo {
                let datagram = DatagramChannel(
                    endpoint: endpoint, flowID: flow.flowID, token: flow.token,
                    sendKey: keys.datagramSendKey, receiveKey: keys.datagramReceiveKey)
                if await datagram.start() {
                    members[playerID]?.datagram = datagram
                    startDatagramReceive(from: datagram, playerID: playerID)
                } else {
                    await datagram.cancel()
                }
            }

            try await sendMessage(
                .welcome(
                    spaceName: spaceName, mapVersion: map.contentHash,
                    hostAllowsUDP: allowUDP, roster: currentRoster()),
                to: playerID)
            await broadcastRoster()

            // Stay on the line for tunnel traffic until they leave or drop.
            while let frame = try await frames.next() {
                switch try SessionMessage(decoding: receiveCipher.open(frame)) {
                case .leave:
                    await removeMember(playerID)
                    return
                case .worldFrame(let payload):
                    switch try? WorldPayload(decoding: [UInt8](payload)) {
                    case .input(let input):
                        applyInput(playerID: playerID, frame: input)
                    case .voice(_, let seq, let opus):
                        await fanOutVoice(fromPlayerID: playerID, seq: seq, opus: opus)
                    default:
                        break
                    }
                case .transportSelected(let useUDP):
                    // Copy-modify-writeback: reading `members` inside a
                    // subscript assignment overlaps exclusive access.
                    if var member = members[playerID] {
                        member.wantsUDP = useUDP && member.datagram != nil
                        members[playerID] = member
                    }
                default:
                    break
                }
            }
            await removeMember(playerID)
        } catch {
            await tunnel.cancel()
            // If they made it into the roster before the error, drop them out.
            if let admittedPlayerID {
                await removeMember(admittedPlayerID)
            }
        }
    }

    private func startDatagramReceive(from datagram: DatagramChannel, playerID: String) {
        tasks.append(
            Task { [weak self] in
                for await payload in datagram.incoming {
                    switch try? WorldPayload(decoding: payload) {
                    case .input(let input):
                        await self?.applyInput(playerID: playerID, frame: input)
                    case .voice(_, let seq, let opus):
                        await self?.fanOutVoice(fromPlayerID: playerID, seq: seq, opus: opus)
                    default:
                        break
                    }
                }
            })
    }

    // MARK: Voice fan-out (PLAN §8: the host is a micro-SFU)

    /// The host's own mic frames enter the same fan-out as everyone else's.
    public func sendHostVoice(seq: UInt32, opus: Data) async {
        await fanOutVoice(fromPlayerID: identity.playerID, seq: seq, opus: opus)
    }

    /// Forward one voice frame to every member within earshot of the speaker.
    /// speakerID is set from the *verified* pair identity — no spoofing — and
    /// the payload is never decoded here, only re-sealed per pair.
    private func fanOutVoice(fromPlayerID: String, seq: UInt32, opus: Data) async {
        guard let speakerPosition = world[fromPlayerID]?.position else { return }
        let speakerWireID = PlayerWireID.prefix(fromHexID: fromPlayerID)
        guard
            let bytes = try? WorldPayload.voice(speakerID: speakerWireID, seq: seq, opus: opus)
                .encoded()
        else { return }

        for (memberID, member) in members where memberID != fromPlayerID {
            guard let listenerPosition = world[memberID]?.position,
                ProximityRules.standard.isAudible(
                    atDistance: speakerPosition.distance(to: listenerPosition))
            else { continue }
            if member.wantsUDP, let datagram = member.datagram {
                await datagram.send(bytes)
            } else {
                try? await sendMessage(.worldFrame(payload: Data(bytes)), to: memberID)
            }
        }

        // The host listens too.
        if fromPlayerID != identity.playerID,
            let hostPosition = world[identity.playerID]?.position,
            ProximityRules.standard.isAudible(
                atDistance: speakerPosition.distance(to: hostPosition))
        {
            eventsContinuation.yield(.voiceReceived(speakerID: speakerWireID, seq: seq, opus: opus))
        }
    }

    private func removeMember(_ playerID: String) async {
        guard let member = members.removeValue(forKey: playerID) else { return }
        world.removeValue(forKey: playerID)
        await member.datagram?.cancel()
        await member.tunnel.cancel()
        try? directory.markLeft(id: playerID)
        await broadcastRoster()
    }

    // MARK: Roster

    private func currentRoster() -> [RosterEntry] {
        let host = RosterEntry(
            playerID: identity.playerID, displayName: hostDisplayName,
            avatarPreset: hostAvatarPreset, isOnline: true)
        return [host] + members.values.map(\.entry).sorted { $0.displayName < $1.displayName }
    }

    private func sendMessage(_ message: SessionMessage, to playerID: String) async throws {
        guard var member = members[playerID] else { return }
        let sealed = try member.sendCipher.seal(message.encoded())
        members[playerID] = member
        try await member.tunnel.send(frame: sealed)
    }

    private func broadcastRoster() async {
        let roster = currentRoster()
        eventsContinuation.yield(.rosterChanged(roster))
        for playerID in members.keys {
            try? await sendMessage(.rosterUpdate(roster: roster), to: playerID)
        }
    }
}
