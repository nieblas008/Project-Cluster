import NIOCore

/// Phase 0 control plane: a line-oriented PING/PONG so deploys are verifiable
/// end-to-end (`nc <relay-ip> 7600` → PING → PONG). Phase 1 replaces this with
/// the real TLS session protocol (register / lookup / introduce).
public final class ControlPingHandler: ChannelInboundHandler {
    public typealias InboundIn = ByteBuffer
    public typealias OutboundOut = ByteBuffer

    private var pending = ""

    public init() {}

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var buffer = unwrapInboundIn(data)
        if let chunk = buffer.readString(length: buffer.readableBytes) {
            pending += chunk
        }
        // Refuse to buffer unbounded garbage from port scanners.
        if pending.count > 1024 {
            context.close(promise: nil)
            return
        }
        // "\r\n" is a single Character in Swift — match it explicitly or CRLF
        // lines are never detected.
        while let newline = pending.firstIndex(where: { $0 == "\n" || $0 == "\r\n" }) {
            let line = Self.trimmed(pending[..<newline])
            pending.removeSubrange(...newline)
            handle(line: line, context: context)
        }
    }

    private func handle(line: String, context: ChannelHandlerContext) {
        switch line.uppercased() {
        case "PING":
            respond(RelayInfo.banner, context: context)
        case "QUIT":
            context.close(promise: nil)
        case "":
            break
        default:
            respond("ERR unknown-command", context: context)
        }
    }

    private func respond(_ line: String, context: ChannelHandlerContext) {
        let buffer = context.channel.allocator.buffer(string: line + "\n")
        context.writeAndFlush(wrapOutboundOut(buffer), promise: nil)
    }

    /// Manual trim keeps this target Foundation-free.
    static func trimmed(_ text: Substring) -> String {
        let whitespace: Set<Character> = [" ", "\t", "\r"]
        var slice = text
        while let first = slice.first, whitespace.contains(first) { slice.removeFirst() }
        while let last = slice.last, whitespace.contains(last) { slice.removeLast() }
        return String(slice)
    }
}
