import NIOCore

/// Phase 0 data plane: echoes datagrams back to their sender, which is exactly
/// what the app's Connectivity Doctor needs to prove "UDP works from this
/// network to the relay". Phase 1 replaces echo with per-pair flow forwarding.
public final class UDPEchoHandler: ChannelInboundHandler {
    public typealias InboundIn = AddressedEnvelope<ByteBuffer>
    public typealias OutboundOut = AddressedEnvelope<ByteBuffer>

    public init() {}

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let envelope = unwrapInboundIn(data)
        let reply = AddressedEnvelope(remoteAddress: envelope.remoteAddress, data: envelope.data)
        context.writeAndFlush(wrapOutboundOut(reply), promise: nil)
    }
}
