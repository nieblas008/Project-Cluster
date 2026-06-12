import ClusterProtocol
import Foundation
import Logging
import NIOCore

/// Per-connection control-plane state machine. Lives in the pipeline behind
/// TLS; on splice it goes transparent, installs glue on both legs, and removes
/// itself. See PLAN §2 and ADR 0001 for the session choreography.
public final class ControlHandler: ChannelInboundHandler, RemovableChannelHandler {
    public typealias InboundIn = ByteBuffer
    public typealias InboundOut = ByteBuffer
    public typealias OutboundOut = ByteBuffer

    enum Phase {
        case awaitingHello
        case awaitingCommand(ControlRole)
        case hostRegistered(code: String)
        case joinerParked(pairID: UInt32)
        case probing
        /// Glue is (being) installed; pass reads through untouched.
        case spliced
    }

    /// Pairs not attached within this window are cancelled (host app gone?).
    static let pairTimeout = TimeAmount.seconds(30)

    private let registry: SessionRegistry
    private let flows: FlowTable
    private let logger: Logger
    private var assembler = FrameAssembler()
    private var phase = Phase.awaitingHello
    private var parkTimeout: Scheduled<Void>?

    public init(registry: SessionRegistry, flows: FlowTable, logger: Logger) {
        self.registry = registry
        self.flows = flows
        self.logger = logger
    }

    // MARK: Reads

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        if case .spliced = phase {
            context.fireChannelRead(data)
            return
        }
        var buffer = unwrapInboundIn(data)
        if let bytes = buffer.readBytes(length: buffer.readableBytes) {
            assembler.append(bytes)
        }
        do {
            while let payload = try assembler.next() {
                try handle(message: ControlMessage(decoding: payload), context: context)
                if case .spliced = phase { break }
            }
        } catch {
            fail(context: context, "protocol violation")
        }
    }

    private func handle(message: ControlMessage, context: ChannelHandlerContext) throws {
        // Pings are answered in every phase — the keepalive must never depend
        // on session state.
        if case .ping(let nonce) = message {
            Self.send(.pong(nonce: nonce), to: context.channel)
            return
        }

        switch (phase, message) {
        case (.awaitingHello, .clientHello(let version, let role)):
            guard version == ProtocolInfo.wireVersion else {
                Self.send(
                    .error(message: "wire version \(version) unsupported (relay: \(ProtocolInfo.wireVersion))"),
                    to: context.channel)
                context.close(promise: nil)
                return
            }
            phase = role == .probe ? .probing : .awaitingCommand(role)

        case (.awaitingCommand(.host), .registerHost(let key, let spaceName)):
            guard key.count == 32 else {
                fail(context: context, "bad session key")
                return
            }
            let code = registry.register(
                spaceName: spaceName, hostSessionKey: key, hostChannel: context.channel)
            phase = .hostRegistered(code: code)
            logger.info("session registered code=\(code) space=\"\(spaceName)\"")
            Self.send(.registerAck(code: code), to: context.channel)

        case (.awaitingCommand(.joiner), .joinRequest(let code)):
            guard let (pairID, session) = registry.createPair(code: code, joinerChannel: context.channel)
            else {
                Self.send(.joinDenied(reason: "No session with that code."), to: context.channel)
                context.close(promise: nil)
                return
            }
            phase = .joinerParked(pairID: pairID)
            parkedHostChannel = session.hostChannel
            logger.info("join request code=\(session.code) pair=\(pairID)")
            Self.send(
                .joinAccepted(
                    pairID: pairID, hostSessionKey: session.hostSessionKey,
                    spaceName: session.spaceName),
                to: context.channel)
            Self.send(.incomingPair(pairID: pairID), to: session.hostChannel)
            scheduleParkTimeout(pairID: pairID, session: session, context: context)

        case (.awaitingCommand(.attach), .attach(let pairID)):
            guard let pair = registry.claimPair(pairID: pairID) else {
                fail(context: context, "unknown pair")
                return
            }
            logger.info("splicing pair=\(pairID)")
            // Hand each side its UDP flow credentials, then go transparent.
            let flow = flows.createFlow()
            Self.send(.dataPlane(flowID: flow.flowID, token: flow.hostToken), to: context.channel)
            Self.send(.dataPlane(flowID: flow.flowID, token: flow.joinerToken), to: pair.joinerChannel)
            splice(hostLeg: context, joinerChannel: pair.joinerChannel)

        case (.probing, _), (.hostRegistered, _), (.joinerParked, _):
            // Nothing else is legal in these phases (pings handled above).
            fail(context: context, "unexpected message")

        default:
            fail(context: context, "unexpected message")
        }
    }

    // MARK: Splice

    private func splice(hostLeg: ChannelHandlerContext, joinerChannel: Channel) {
        // Speaking into the tunnel before spliceBegin is a protocol violation;
        // refusing beats heroically replaying half-read bytes.
        guard assembler.bufferedByteCount == 0 else {
            fail(context: hostLeg, "early tunnel bytes")
            joinerChannel.close(promise: nil)
            return
        }
        phase = .spliced
        let hostChannel = hostLeg.channel
        let (hostGlue, joinerGlue) = GlueHandler.matchedPair()

        Self.send(.spliceBegin, to: hostChannel)
        Self.send(.spliceBegin, to: joinerChannel)

        // Order per leg: go transparent (phase = .spliced makes channelRead
        // pass through) → add glue after this handler → remove this handler.
        // Reads never hit a gap.
        hostChannel.eventLoop.execute {
            do {
                try hostChannel.pipeline.syncOperations.addHandler(hostGlue)
                hostChannel.pipeline.removeHandler(self, promise: nil)
            } catch {
                self.logger.error("host-leg splice failed: \(error)")
                hostChannel.close(promise: nil)
                joinerChannel.close(promise: nil)
            }
        }
        joinerChannel.eventLoop.execute {
            joinerChannel.pipeline.handler(type: ControlHandler.self).whenComplete { result in
                switch result {
                case .success(let joinerControl):
                    guard joinerControl.becomeSpliced() else {
                        self.logger.error("joiner sent early tunnel bytes; closing pair")
                        hostChannel.close(promise: nil)
                        joinerChannel.close(promise: nil)
                        return
                    }
                    do {
                        try joinerChannel.pipeline.syncOperations.addHandler(joinerGlue)
                        joinerChannel.pipeline.removeHandler(joinerControl, promise: nil)
                    } catch {
                        self.logger.error("joiner-leg splice failed: \(error)")
                        hostChannel.close(promise: nil)
                        joinerChannel.close(promise: nil)
                    }
                case .failure(let error):
                    self.logger.error("joiner control handler missing: \(error)")
                    hostChannel.close(promise: nil)
                    joinerChannel.close(promise: nil)
                }
            }
        }
    }

    /// Called on the *joiner's* handler (from its own event loop) when its
    /// pair is being spliced: flip transparent, cancel the park timeout.
    /// Returns false if the joiner already violated the protocol.
    func becomeSpliced() -> Bool {
        phase = .spliced
        parkTimeout?.cancel()
        parkTimeout = nil
        return assembler.bufferedByteCount == 0
    }

    // MARK: Park timeout & teardown

    private func scheduleParkTimeout(
        pairID: UInt32, session: SessionRegistry.Session, context: ChannelHandlerContext
    ) {
        parkTimeout = context.eventLoop.scheduleTask(in: Self.pairTimeout) { [weak self] in
            guard let self, case .joinerParked(let parked) = self.phase, parked == pairID else { return }
            self.logger.info("pair=\(pairID) timed out waiting for host attach")
            _ = self.registry.cancelPair(pairID: pairID)
            Self.send(.peerGone(pairID: pairID), to: session.hostChannel)
            Self.send(.joinDenied(reason: "The host did not answer in time."), to: context.channel)
            context.close(promise: nil)
        }
    }

    public func channelInactive(context: ChannelHandlerContext) {
        parkTimeout?.cancel()
        switch phase {
        case .hostRegistered(let code):
            if let (_, orphans) = registry.unregisterHost(channel: context.channel) {
                logger.info("session ended code=\(code) orphanedPairs=\(orphans.count)")
                for pair in orphans {
                    Self.send(.joinDenied(reason: "The host went away."), to: pair.joinerChannel)
                    pair.joinerChannel.close(promise: nil)
                }
            }
        case .joinerParked(let pairID):
            if registry.cancelPair(pairID: pairID) != nil {
                logger.info("parked joiner left pair=\(pairID)")
                if let host = parkedHostChannel {
                    Self.send(.peerGone(pairID: pairID), to: host)
                }
            }
        default:
            break
        }
        context.fireChannelInactive()
    }

    /// Set when this connection parks as a joiner, so its death can be
    /// reported to the right host.
    private var parkedHostChannel: Channel?

    // MARK: Helpers

    private func fail(context: ChannelHandlerContext, _ reason: String) {
        Self.send(.error(message: reason), to: context.channel)
        context.close(promise: nil)
    }

    static func send(_ message: ControlMessage, to channel: Channel) {
        guard let payload = try? message.encoded(), let frame = try? Frame.encode(payload) else {
            return
        }
        var buffer = channel.allocator.buffer(capacity: frame.count)
        buffer.writeBytes(frame)
        channel.writeAndFlush(buffer, promise: nil)
    }
}
