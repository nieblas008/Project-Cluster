import NIOCore

/// The splice: two of these, partnered, pipe bytes between two channels.
/// Installed after `spliceBegin`; from then on the relay is a dumb pipe and
/// everything flowing through is end-to-end ciphertext it cannot open.
public final class GlueHandler: ChannelDuplexHandler {
    public typealias InboundIn = ByteBuffer
    public typealias InboundOut = ByteBuffer
    public typealias OutboundIn = ByteBuffer
    public typealias OutboundOut = ByteBuffer

    private var partner: GlueHandler?
    private var context: ChannelHandlerContext?

    private init() {}

    public static func matchedPair() -> (GlueHandler, GlueHandler) {
        let a = GlueHandler()
        let b = GlueHandler()
        a.partner = b
        b.partner = a
        return (a, b)
    }

    public func handlerAdded(context: ChannelHandlerContext) {
        self.context = context
    }

    public func handlerRemoved(context: ChannelHandlerContext) {
        self.context = nil
        partner = nil
    }

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        partner?.forward(unwrapInboundIn(data))
    }

    public func channelInactive(context: ChannelHandlerContext) {
        // One side hung up: tear down the other half of the pipe too.
        partner?.closeFromPartner()
        context.fireChannelInactive()
    }

    public func channelWritabilityChanged(context: ChannelHandlerContext) {
        // Backpressure: if we can't drain to our side, stop reading the other.
        partner?.setReading(enabled: context.channel.isWritable)
    }

    private func forward(_ buffer: ByteBuffer) {
        guard let context else { return }
        context.eventLoop.execute {
            context.writeAndFlush(self.wrapOutboundOut(buffer), promise: nil)
        }
    }

    private func closeFromPartner() {
        guard let context else { return }
        context.eventLoop.execute {
            context.close(promise: nil)
        }
    }

    private func setReading(enabled: Bool) {
        guard let context else { return }
        context.eventLoop.execute {
            _ = context.channel.setOption(ChannelOptions.autoRead, value: enabled)
        }
    }
}
