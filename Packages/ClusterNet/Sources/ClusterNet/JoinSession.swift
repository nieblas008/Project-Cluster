import ClusterProtocol
import CryptoKit
import Foundation

public enum JoinSessionEvent: Sendable {
    /// Human-readable progress for the lobby UI.
    case status(String)
    case knockPending
    case welcomed(spaceName: String, roster: [RosterEntry])
    case rosterChanged([RosterEntry])
    /// Which road world traffic took after probing (ADR 0002) — for the UI badge.
    case transport(usingUDP: Bool)
    case worldSnapshot(WorldSnapshot)
    /// A speaker within earshot (the host already proximity-filtered).
    case voiceReceived(speakerID: UInt64, seq: UInt32, opus: Data)
    case denied(reason: String)
    case ended(reason: String)
}

/// The joining side: one connection that starts as control (code lookup),
/// becomes the end-to-end tunnel after the splice, and — once welcomed —
/// probes its UDP path and starts moving (Phase 2).
public actor JoinSession {
    public nonisolated let events: AsyncStream<JoinSessionEvent>
    private let eventsContinuation: AsyncStream<JoinSessionEvent>.Continuation

    private let endpoint: RelayEndpoint
    private let identity: PlayerIdentity
    private let displayName: String
    private let avatarPreset: String
    /// Bundled map — its hash must match the host's (welcome.mapVersion).
    private let mapHash: String
    /// False when Settings → Connection forces TCP (ADR 0002).
    private let preferUDP: Bool

    private var connection: FrameConnection?
    private var sendCipher: SecureChannelCipher?
    private var datagram: DatagramChannel?
    private var usingUDP = false
    private var task: Task<Void, Never>?
    private var datagramTask: Task<Void, Never>?

    public init(
        endpoint: RelayEndpoint, identity: PlayerIdentity,
        displayName: String, avatarPreset: String,
        mapHash: String, preferUDP: Bool
    ) {
        self.endpoint = endpoint
        self.identity = identity
        self.displayName = displayName
        self.avatarPreset = avatarPreset
        self.mapHash = mapHash
        self.preferUDP = preferUDP
        (events, eventsContinuation) = AsyncStream.makeStream()
    }

    public func start(code rawCode: String) async {
        let code = rawCode.uppercased().trimmingCharacters(in: .whitespaces)
        task = Task { [weak self] in
            await self?.run(code: code)
        }
    }

    public func leave() async {
        await sendSealed(.leave)
        task?.cancel()
        datagramTask?.cancel()
        await datagram?.cancel()
        await connection?.cancel()
        eventsContinuation.yield(.ended(reason: "You left."))
        eventsContinuation.finish()
    }

    /// The scene's movement output, ~20 Hz while moving. Rides whichever road
    /// the probe selected.
    public func sendInput(_ frame: InputFrame) async {
        await sendWorld(.input(frame))
    }

    /// One mic frame (the engine already gated silence).
    public func sendVoice(seq: UInt32, opus: Data) async {
        let speakerID = PlayerWireID.prefix(fromHexID: identity.playerID)
        await sendWorld(.voice(speakerID: speakerID, seq: seq, opus: opus))
    }

    private func sendWorld(_ payload: WorldPayload) async {
        guard let bytes = try? payload.encoded() else { return }
        if usingUDP, let datagram {
            await datagram.send(bytes)
        } else {
            await sendSealed(.worldFrame(payload: Data(bytes)))
        }
    }

    private func sendSealed(_ message: SessionMessage) async {
        guard var cipher = sendCipher, let connection else { return }
        guard let sealed = try? cipher.seal(message.encoded()) else { return }
        sendCipher = cipher
        try? await connection.send(frame: sealed)
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
            var flowInfo: (flowID: UInt32, token: UInt64)?

            // Control stage: accepted (or denied) → flow credentials → splice.
            controlStage: while let frame = try await frames.next() {
                switch try ControlMessage(decoding: frame) {
                case .joinAccepted(_, let key, _):
                    hostSessionKey = key
                    eventsContinuation.yield(.status("Found the session — waiting for the host…"))
                case .joinDenied(let reason):
                    eventsContinuation.yield(.denied(reason: reason))
                    return
                case .dataPlane(let flowID, let token):
                    flowInfo = (flowID, token)
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
            self.sendCipher = SecureChannelCipher(key: keys.sendKey)

            let hello = SessionMessage.joinHello(
                identityKey: identity.publicKeyData,
                displayName: displayName,
                avatarPreset: avatarPreset,
                inviteSecret: code,
                signature: try JoinSignature.sign(identity: identity, transcriptHash: keys.transcriptHash)
            )
            await sendSealed(hello)
            eventsContinuation.yield(.status("Knocking…"))

            while let frame = try await frames.next() {
                switch try SessionMessage(decoding: receiveCipher.open(frame)) {
                case .knockPending:
                    eventsContinuation.yield(.knockPending)
                case .welcome(let spaceName, let mapVersion, let hostAllowsUDP, let roster):
                    guard mapVersion == mapHash else {
                        eventsContinuation.yield(
                            .denied(
                                reason: "Map version mismatch — host and joiners must run "
                                    + "the same app version."))
                        await connection.cancel()
                        return
                    }
                    eventsContinuation.yield(.welcomed(spaceName: spaceName, roster: roster))
                    await negotiateTransport(hostAllowsUDP: hostAllowsUDP, flowInfo: flowInfo, keys: keys)
                case .rosterUpdate(let roster):
                    eventsContinuation.yield(.rosterChanged(roster))
                case .worldFrame(let payload):
                    yieldWorld(try? WorldPayload(decoding: [UInt8](payload)))
                case .denied(let reason):
                    eventsContinuation.yield(.denied(reason: reason))
                    return
                case .leave:
                    eventsContinuation.yield(.ended(reason: "The host ended the session."))
                    return
                case .joinHello, .transportSelected:
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

    private func yieldWorld(_ payload: WorldPayload?) {
        switch payload {
        case .snapshot(let snapshot):
            eventsContinuation.yield(.worldSnapshot(snapshot))
        case .voice(let speakerID, let seq, let opus):
            eventsContinuation.yield(.voiceReceived(speakerID: speakerID, seq: seq, opus: opus))
        default:
            break
        }
    }

    /// Probe the UDP road; tell the host which one to use for us (ADR 0002).
    private func negotiateTransport(
        hostAllowsUDP: Bool, flowInfo: (flowID: UInt32, token: UInt64)?, keys: SessionKeys
    ) async {
        if preferUDP, hostAllowsUDP, let flow = flowInfo {
            let channel = DatagramChannel(
                endpoint: endpoint, flowID: flow.flowID, token: flow.token,
                sendKey: keys.datagramSendKey, receiveKey: keys.datagramReceiveKey)
            if await channel.start() {
                datagram = channel
                usingUDP = true
                datagramTask = Task { [weak self] in
                    for await payload in channel.incoming {
                        await self?.yieldWorld(try? WorldPayload(decoding: payload))
                    }
                }
            } else {
                await channel.cancel()
            }
        }
        await sendSealed(.transportSelected(useUDP: usingUDP))
        eventsContinuation.yield(.transport(usingUDP: usingUDP))
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
