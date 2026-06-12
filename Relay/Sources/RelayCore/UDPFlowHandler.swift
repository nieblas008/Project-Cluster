import ClusterProtocol
import Logging
import NIOCore

/// The UDP data plane (ADR 0002), replacing Phase 0's pure echo:
/// - `CBND` bind packets register a side's observed address and are echoed
///   back as the bind-ack — which doubles as the client's UDP-works probe.
/// - Data packets (flowID-prefixed) are forwarded to the flow's other side,
///   contents untouched (they're end-to-end sealed).
/// - Anything else small from an unknown sender is echoed: the Connectivity
///   Doctor's probe keeps working unchanged.
public final class UDPFlowHandler: ChannelInboundHandler {
    public typealias InboundIn = AddressedEnvelope<ByteBuffer>
    public typealias OutboundOut = AddressedEnvelope<ByteBuffer>

    private let flows: FlowTable
    private let logger: Logger

    public init(flows: FlowTable, logger: Logger) {
        self.flows = flows
        self.logger = logger
    }

    public func handlerAdded(context: ChannelHandlerContext) {
        scheduleSweep(on: context.eventLoop)
    }

    private func scheduleSweep(on eventLoop: EventLoop) {
        eventLoop.scheduleTask(in: .seconds(60)) { [flows, logger] in
            let dropped = flows.sweep()
            if dropped > 0 {
                logger.info("swept \(dropped) idle UDP flows")
            }
            self.scheduleSweep(on: eventLoop)
        }
    }

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let envelope = unwrapInboundIn(data)
        var buffer = envelope.data
        guard let bytes = buffer.getBytes(at: buffer.readerIndex, length: buffer.readableBytes)
        else { return }

        if let bind = DatagramWire.decodeBind(bytes) {
            if flows.bind(flowID: bind.flowID, token: bind.token, address: envelope.remoteAddress) != nil {
                // Ack = echo the bind. The sender learns its UDP path works.
                context.writeAndFlush(
                    wrapOutboundOut(
                        AddressedEnvelope(remoteAddress: envelope.remoteAddress, data: envelope.data)),
                    promise: nil)
            }
            return
        }

        if let flowID = DatagramWire.peekFlowID(bytes) {
            if let destination = flows.destination(flowID: flowID, from: envelope.remoteAddress) {
                context.writeAndFlush(
                    wrapOutboundOut(AddressedEnvelope(remoteAddress: destination, data: envelope.data)),
                    promise: nil)
            }
            return
        }

        // Doctor probe: small unknown packet → echo.
        if bytes.count <= 16 {
            context.writeAndFlush(
                wrapOutboundOut(
                    AddressedEnvelope(remoteAddress: envelope.remoteAddress, data: envelope.data)),
                promise: nil)
        }
    }
}
