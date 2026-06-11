import ClusterProtocol
import CryptoKit
import Foundation

public enum HostSessionEvent: Sendable {
    case registered(code: String)
    /// A never-seen identity wants in; answer via `resolveKnock`.
    case knock(playerID: String, displayName: String)
    case rosterChanged([RosterEntry])
    case ended(reason: String)
}

/// The hosting side of Phase 1: registers with the relay, answers incoming
/// pairs with an attach connection, runs the responder handshake, gates entry
/// (signature → blocklist → knock), and owns the lobby roster.
public actor HostSession {
    public nonisolated let events: AsyncStream<HostSessionEvent>
    private let eventsContinuation: AsyncStream<HostSessionEvent>.Continuation

    private let endpoint: RelayEndpoint
    private let identity: PlayerIdentity
    private let directory: any HostDirectory
    private let spaceName: String
    private let hostDisplayName: String
    private let hostAvatarPreset: String
    private let sessionKey = HostSessionKey()

    private var control: FrameConnection?
    private var sessionCode: String?

    private struct Member {
        var entry: RosterEntry
        var tunnel: FrameConnection
        var sendCipher: SecureChannelCipher
    }
    private var members: [String: Member] = [:]
    private var knockDecisions: [String: CheckedContinuation<Bool, Never>] = [:]
    private var tasks: [Task<Void, Never>] = []

    public init(
        endpoint: RelayEndpoint,
        identity: PlayerIdentity,
        directory: any HostDirectory,
        spaceName: String,
        hostDisplayName: String,
        hostAvatarPreset: String
    ) {
        self.endpoint = endpoint
        self.identity = identity
        self.directory = directory
        self.spaceName = spaceName
        self.hostDisplayName = hostDisplayName
        self.hostAvatarPreset = hostAvatarPreset
        (events, eventsContinuation) = AsyncStream.makeStream()
    }

    // MARK: Lifecycle

    /// Connects, registers, and returns the session code.
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
        eventsContinuation.yield(.registered(code: code))
        eventsContinuation.yield(.rosterChanged(currentRoster()))
        startPings(on: control)
        return code
    }

    public func stop() async {
        for task in tasks { task.cancel() }
        for member in members.values {
            await member.tunnel.cancel()
        }
        await control?.cancel()
        members.removeAll()
        eventsContinuation.yield(.ended(reason: "Hosting stopped."))
        eventsContinuation.finish()
    }

    /// UI's answer to a `.knock` event.
    public func resolveKnock(playerID: String, approve: Bool) {
        knockDecisions.removeValue(forKey: playerID)?.resume(returning: approve)
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

    // MARK: Serving a joiner

    private func serveIncomingPair(pairID: UInt32) async {
        let tunnel = FrameConnection(endpoint: endpoint)
        var admittedPlayerID: String?
        do {
            try await tunnel.start()
            try await tunnel.send(.clientHello(wireVersion: ProtocolInfo.wireVersion, role: .attach))
            try await tunnel.send(.attach(pairID: pairID))

            var frames = tunnel.incomingFrames.makeAsyncIterator()
            guard let first = try await frames.next(),
                case .spliceBegin = try ControlMessage(decoding: first)
            else { throw ConnectionError.protocolViolation }

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
            try await sendMessage(.welcome(spaceName: spaceName, roster: currentRoster()), to: playerID)
            await broadcastRoster()

            // Stay on the line until they leave or drop.
            while let frame = try await frames.next() {
                if case .leave = try SessionMessage(decoding: receiveCipher.open(frame)) {
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

    private func removeMember(_ playerID: String) async {
        guard let member = members.removeValue(forKey: playerID) else { return }
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
