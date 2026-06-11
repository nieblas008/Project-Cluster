import NIOCore
import NIOEmbedded
import Testing

@testable import RelayCore

@Suite struct ControlPingHandlerTests {
    func makeChannel() throws -> EmbeddedChannel {
        let channel = EmbeddedChannel()
        try channel.pipeline.syncOperations.addHandler(ControlPingHandler())
        return channel
    }

    @Test func pingAnswersWithBanner() throws {
        let channel = try makeChannel()
        try channel.writeInbound(ByteBuffer(string: "PING\n"))

        let reply = try channel.readOutbound(as: ByteBuffer.self)
        let text = reply.flatMap { $0.getString(at: 0, length: $0.readableBytes) }
        #expect(text == RelayInfo.banner + "\n")
    }

    @Test func pingSurvivesSplitPackets() throws {
        let channel = try makeChannel()
        try channel.writeInbound(ByteBuffer(string: "PI"))
        #expect(try channel.readOutbound(as: ByteBuffer.self) == nil)

        try channel.writeInbound(ByteBuffer(string: "NG\r\n"))
        let reply = try channel.readOutbound(as: ByteBuffer.self)
        let text = reply.flatMap { $0.getString(at: 0, length: $0.readableBytes) }
        #expect(text == RelayInfo.banner + "\n")
    }

    @Test func unknownCommandsGetAnError() throws {
        let channel = try makeChannel()
        try channel.writeInbound(ByteBuffer(string: "HACKME\n"))
        let reply = try channel.readOutbound(as: ByteBuffer.self)
        let text = reply.flatMap { $0.getString(at: 0, length: $0.readableBytes) }
        #expect(text == "ERR unknown-command\n")
    }

    @Test func oversizedGarbageClosesTheConnection() throws {
        let channel = try makeChannel()
        try channel.writeInbound(ByteBuffer(string: String(repeating: "x", count: 2000)))
        #expect(!channel.isActive)
    }

    @Test func trimmedHandlesEdges() {
        #expect(ControlPingHandler.trimmed("  PING\r") == "PING")
        #expect(ControlPingHandler.trimmed("") == "")
        #expect(ControlPingHandler.trimmed(" \t ") == "")
    }
}
