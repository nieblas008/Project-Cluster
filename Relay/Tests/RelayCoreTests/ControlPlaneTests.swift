import ClusterProtocol
import Foundation
import Logging
import NIOCore
import NIOEmbedded
import Testing

@testable import RelayCore

/// Drives ControlHandler instances over EmbeddedChannels sharing one event
/// loop, decoding outbound frames back into ControlMessages.
private struct Harness {
    let loop = EmbeddedEventLoop()
    let registry = SessionRegistry()
    let logger = Logger(label: "test")

    func makeChannel() throws -> EmbeddedChannel {
        let channel = EmbeddedChannel(loop: loop)
        try channel.pipeline.syncOperations.addHandler(
            ControlHandler(registry: registry, logger: logger))
        return channel
    }

    func send(_ message: ControlMessage, to channel: EmbeddedChannel) throws {
        let frame = try Frame.encode(message.encoded())
        var buffer = channel.allocator.buffer(capacity: frame.count)
        buffer.writeBytes(frame)
        try channel.writeInbound(buffer)
        loop.run()
    }

    func drainMessages(from channel: EmbeddedChannel) throws -> [ControlMessage] {
        loop.run()
        var assembler = FrameAssembler()
        while let buffer = try channel.readOutbound(as: ByteBuffer.self) {
            assembler.append(buffer.getBytes(at: 0, length: buffer.readableBytes) ?? [])
        }
        var messages: [ControlMessage] = []
        while let payload = try assembler.next() {
            messages.append(try ControlMessage(decoding: payload))
        }
        return messages
    }

    func register(spaceName: String = "The Mansion") throws -> (EmbeddedChannel, code: String) {
        let host = try makeChannel()
        try send(.clientHello(wireVersion: ProtocolInfo.wireVersion, role: .host), to: host)
        try send(
            .registerHost(sessionPublicKey: Data(repeating: 7, count: 32), spaceName: spaceName),
            to: host)
        let messages = try drainMessages(from: host)
        guard case .registerAck(let code) = messages.last else {
            throw TestError.unexpected("no registerAck, got \(messages)")
        }
        return (host, code)
    }

    enum TestError: Error { case unexpected(String) }
}

@Suite struct SessionRegistryTests {
    @Test func codesAreSixUnambiguousCharacters() {
        for _ in 0..<50 {
            let code = SessionRegistry.makeCode()
            #expect(code.count == 6)
            #expect(code.allSatisfy { SessionRegistry.codeAlphabet.contains($0) })
        }
    }

    @Test func pairsAreClaimableExactlyOnce() throws {
        let harness = Harness()
        let (_, code) = try harness.register()
        let joiner = try harness.makeChannel()

        let pair = harness.registry.createPair(code: code, joinerChannel: joiner)
        let pairID = try #require(pair).pairID
        #expect(harness.registry.claimPair(pairID: pairID) != nil)
        #expect(harness.registry.claimPair(pairID: pairID) == nil)
    }

    @Test func codeLookupIsCaseInsensitive() throws {
        let harness = Harness()
        let (_, code) = try harness.register()
        #expect(harness.registry.session(code: code.lowercased()) != nil)
    }
}

@Suite struct ControlHandlerTests {
    @Test func hostRegistrationYieldsACode() throws {
        let harness = Harness()
        let (_, code) = try harness.register()
        #expect(code.count == 6)
        #expect(harness.registry.sessionCount == 1)
    }

    @Test func probeGetsPong() throws {
        let harness = Harness()
        let probe = try harness.makeChannel()
        try harness.send(.clientHello(wireVersion: ProtocolInfo.wireVersion, role: .probe), to: probe)
        try harness.send(.ping(nonce: 99), to: probe)
        #expect(try harness.drainMessages(from: probe) == [.pong(nonce: 99)])
    }

    @Test func wrongWireVersionIsRefused() throws {
        let harness = Harness()
        let channel = try harness.makeChannel()
        try harness.send(.clientHello(wireVersion: 999, role: .host), to: channel)
        let messages = try harness.drainMessages(from: channel)
        guard case .error = messages.first else {
            Issue.record("expected error, got \(messages)")
            return
        }
        #expect(!channel.isActive)
    }

    @Test func unknownCodeIsDenied() throws {
        let harness = Harness()
        let joiner = try harness.makeChannel()
        try harness.send(.clientHello(wireVersion: ProtocolInfo.wireVersion, role: .joiner), to: joiner)
        try harness.send(.joinRequest(code: "NOPE99"), to: joiner)
        let messages = try harness.drainMessages(from: joiner)
        guard case .joinDenied = messages.first else {
            Issue.record("expected joinDenied, got \(messages)")
            return
        }
    }

    @Test func fullJoinAttachSpliceForwardsBytesBothWays() throws {
        let harness = Harness()
        let (host, code) = try harness.register()

        // Joiner asks for the code.
        let joiner = try harness.makeChannel()
        try harness.send(.clientHello(wireVersion: ProtocolInfo.wireVersion, role: .joiner), to: joiner)
        try harness.send(.joinRequest(code: code), to: joiner)

        let joinerMessages = try harness.drainMessages(from: joiner)
        guard case .joinAccepted(let pairID, let key, let space) = joinerMessages.first else {
            Issue.record("expected joinAccepted, got \(joinerMessages)")
            return
        }
        #expect(key == Data(repeating: 7, count: 32))
        #expect(space == "The Mansion")
        #expect(try harness.drainMessages(from: host) == [.incomingPair(pairID: pairID)])

        // Host attaches on a fresh connection → both legs get spliceBegin.
        let attach = try harness.makeChannel()
        try harness.send(.clientHello(wireVersion: ProtocolInfo.wireVersion, role: .attach), to: attach)
        try harness.send(.attach(pairID: pairID), to: attach)

        #expect(try harness.drainMessages(from: attach) == [.spliceBegin])
        #expect(try harness.drainMessages(from: joiner) == [.spliceBegin])

        // Raw bytes now flow attach → joiner…
        var msg1 = attach.allocator.buffer(capacity: 8)
        msg1.writeBytes([0xAA, 0xBB])
        try attach.writeInbound(msg1)
        harness.loop.run()
        let forwarded = try joiner.readOutbound(as: ByteBuffer.self)
        #expect(forwarded?.getBytes(at: 0, length: 2) == [0xAA, 0xBB])

        // …and joiner → attach.
        var msg2 = joiner.allocator.buffer(capacity: 8)
        msg2.writeBytes([0xCC])
        try joiner.writeInbound(msg2)
        harness.loop.run()
        let back = try attach.readOutbound(as: ByteBuffer.self)
        #expect(back?.getBytes(at: 0, length: 1) == [0xCC])

        // Closing one leg tears down the other.
        _ = try joiner.finish()
        harness.loop.run()
        #expect(!attach.isActive)
    }

    @Test func hostDeathDeniesParkedJoiners() throws {
        let harness = Harness()
        let (host, code) = try harness.register()

        let joiner = try harness.makeChannel()
        try harness.send(.clientHello(wireVersion: ProtocolInfo.wireVersion, role: .joiner), to: joiner)
        try harness.send(.joinRequest(code: code), to: joiner)
        _ = try harness.drainMessages(from: joiner)

        _ = try host.finish()
        harness.loop.run()

        let messages = try harness.drainMessages(from: joiner)
        guard case .joinDenied = messages.first else {
            Issue.record("expected joinDenied after host death, got \(messages)")
            return
        }
        #expect(harness.registry.sessionCount == 0)
    }
}
