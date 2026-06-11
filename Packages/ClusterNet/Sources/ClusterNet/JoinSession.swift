import ClusterProtocol
import CryptoKit
import Foundation

public enum JoinSessionEvent: Sendable {
    /// Human-readable progress for the lobby UI.
    case status(String)
    case knockPending
    case welcomed(spaceName: String, roster: [RosterEntry])
    case rosterChanged([RosterEntry])
    case denied(reason: String)
    case ended(reason: String)
}

/// The joining side: one connection that starts as control (code lookup) and
/// becomes the end-to-end tunnel after the splice.
public actor JoinSession {
    public nonisolated let events: AsyncStream<JoinSessionEvent>
    private let eventsContinuation: AsyncStream<JoinSessionEvent>.Continuation

    private let endpoint: RelayEndpoint
    private let identity: PlayerIdentity
    private let displayName: String
    private let avatarPreset: String

    private var connection: FrameConnection?
    private var sendCipher: SecureChannelCipher?
    private var task: Task<Void, Never>?

    public init(
        endpoint: RelayEndpoint, identity: PlayerIdentity,
        displayName: String, avatarPreset: String
    ) {
        self.endpoint = endpoint
        self.identity = identity
        self.displayName = displayName
        self.avatarPreset = avatarPreset
        (events, eventsContinuation) = AsyncStream.makeStream()
    }

    public func start(code rawCode: String) async {
        let code = rawCode.uppercased().trimmingCharacters(in: .whitespaces)
        task = Task { [weak self] in
            await self?.run(code: code)
        }
    }

    public func leave() async {
        if var cipher = sendCipher, let connection {
            if let sealed = try? cipher.seal(SessionMessage.leave.encoded()) {
                try? await connection.send(frame: sealed)
            }
            sendCipher = cipher
        }
        task?.cancel()
        await connection?.cancel()
        eventsContinuation.yield(.ended(reason: "You left."))
        eventsContinuation.finish()
    }

    private func run(code: String) async {
        do {
            let connection = FrameConnection(endpoint: endpoint)
            self.connection = connection
            eventsContinuation.yield(.status("Contacting relay…"))
            try await connection.start()
            try await connection.send(.clientHello(wireVersion: ProtocolInfo.wireVersion, role: .joiner))
            try await connection.send(.joinRequest(code: code))

            var frames = connection.incomingFrames.makeAsyncIterator()
            var hostSessionKey: Data?

            // Control stage: accepted (or denied), then the splice marker.
            controlStage: while let frame = try await frames.next() {
                switch try ControlMessage(decoding: frame) {
                case .joinAccepted(_, let key, _):
                    hostSessionKey = key
                    eventsContinuation.yield(.status("Found the session — waiting for the host…"))
                case .joinDenied(let reason):
                    eventsContinuation.yield(.denied(reason: reason))
                    return
                case .spliceBegin:
                    break controlStage
                case .pong:
                    continue
                case .error(let message):
                    throw ConnectionError.failed(message)
                default:
                    throw ConnectionError.protocolViolation
                }
            }
            guard let hostKey = hostSessionKey else { throw ConnectionError.closed }

            // Tunnel stage: NK handshake, joiner initiates.
            eventsContinuation.yield(.status("Securing the tunnel…"))
            let (state, message1) = try SessionHandshake.initiate(
                responderStaticKey: hostKey,
                expectedFingerprint: Data(SHA256.hash(data: hostKey))
            )
            try await connection.send(frame: message1)
            guard let message2 = try await frames.next() else { throw ConnectionError.closed }
            let keys = try state.finalize(message2: message2)
            var receiveCipher = SecureChannelCipher(key: keys.receiveKey)
            var sendCipher = SecureChannelCipher(key: keys.sendKey)

            let hello = SessionMessage.joinHello(
                identityKey: identity.publicKeyData,
                displayName: displayName,
                avatarPreset: avatarPreset,
                inviteSecret: code,
                signature: try JoinSignature.sign(identity: identity, transcriptHash: keys.transcriptHash)
            )
            try await connection.send(frame: sendCipher.seal(hello.encoded()))
            self.sendCipher = sendCipher
            eventsContinuation.yield(.status("Knocking…"))

            while let frame = try await frames.next() {
                switch try SessionMessage(decoding: receiveCipher.open(frame)) {
                case .knockPending:
                    eventsContinuation.yield(.knockPending)
                case .welcome(let spaceName, let roster):
                    eventsContinuation.yield(.welcomed(spaceName: spaceName, roster: roster))
                case .rosterUpdate(let roster):
                    eventsContinuation.yield(.rosterChanged(roster))
                case .denied(let reason):
                    eventsContinuation.yield(.denied(reason: reason))
                    return
                case .leave:
                    eventsContinuation.yield(.ended(reason: "The host ended the session."))
                    return
                case .joinHello:
                    throw ConnectionError.protocolViolation
                }
            }
            eventsContinuation.yield(.ended(reason: "Connection closed."))
        } catch is CancellationError {
            // leave() already emitted.
        } catch {
            eventsContinuation.yield(.ended(reason: "Connection lost: \(error.humanReadable)"))
        }
    }
}

extension Error {
    var humanReadable: String {
        if let connectionError = self as? ConnectionError {
            switch connectionError {
            case .pinMismatch(let actual):
                return "relay certificate mismatch (got \(actual.prefix(12))…)"
            case .failed(let message):
                return message
            case .closed:
                return "closed"
            case .protocolViolation:
                return "protocol violation"
            }
        }
        return String(describing: self)
    }
}
