import Foundation
import Testing

@testable import ClusterProtocol

@Suite struct FramingTests {
    @Test func reassemblesAcrossArbitraryChunks() throws {
        let payload = Array("hello cluster".utf8)
        let frame = try Frame.encode(payload)

        var assembler = FrameAssembler()
        for byte in frame {
            assembler.append([byte])  // worst case: one byte at a time
        }
        #expect(try assembler.next() == payload)
        #expect(try assembler.next() == nil)
    }

    @Test func deliversBackToBackFramesInOrder() throws {
        var assembler = FrameAssembler()
        assembler.append(try Frame.encode([1, 2]) + Frame.encode([3]) + Frame.encode([]))
        #expect(try assembler.next() == [1, 2])
        #expect(try assembler.next() == [3])
        #expect(try assembler.next() == [])
        #expect(try assembler.next() == nil)
    }

    @Test func rejectsOversizedFrameAnnouncements() {
        var assembler = FrameAssembler()
        // Length header claiming 0xFFFF bytes (> maxPayloadLength).
        assembler.append([0xFF, 0xFF])
        #expect(throws: CodecError.invalidValue) {
            _ = try assembler.next()
        }
    }
}

@Suite struct ControlMessageTests {
    @Test(arguments: [
        ControlMessage.clientHello(wireVersion: 1, role: .host),
        .clientHello(wireVersion: 7, role: .probe),
        .registerHost(sessionPublicKey: Data((0..<32).map { UInt8($0) }), spaceName: "The Mansion"),
        .registerAck(code: "K7M2P9"),
        .joinRequest(code: "K7M2P9"),
        .joinAccepted(pairID: 42, hostSessionKey: Data([9, 9, 9]), spaceName: "The Mansion"),
        .joinDenied(reason: "unknown code"),
        .incomingPair(pairID: 42),
        .attach(pairID: 42),
        .spliceBegin,
        .peerGone(pairID: 7),
        .ping(nonce: 0xDEAD_BEEF),
        .pong(nonce: 0xDEAD_BEEF),
        .error(message: "wire version mismatch"),
    ])
    func roundTrips(_ message: ControlMessage) throws {
        #expect(try ControlMessage(decoding: message.encoded()) == message)
    }

    @Test func garbageIsRejectedNotCrashed() {
        #expect(throws: CodecError.self) {
            _ = try ControlMessage(decoding: [0xFF, 0x00])
        }
        #expect(throws: CodecError.self) {
            _ = try ControlMessage(decoding: [])
        }
    }
}

@Suite struct SessionMessageTests {
    @Test func joinHelloRoundTrips() throws {
        let message = SessionMessage.joinHello(
            identityKey: Data(repeating: 0xAB, count: 32),
            displayName: "Dana",
            avatarPreset: "kart-red",
            inviteSecret: "VXKQ23H9TMRW",
            signature: Data(repeating: 0xCD, count: 64)
        )
        #expect(try SessionMessage(decoding: message.encoded()) == message)
    }

    @Test func rosterMessagesRoundTrip() throws {
        let roster = [
            RosterEntry(playerID: "aa11", displayName: "Ricardo", avatarPreset: "default", isOnline: true),
            RosterEntry(playerID: "bb22", displayName: "Dana", avatarPreset: "kart-red", isOnline: false),
        ]
        let welcome = SessionMessage.welcome(spaceName: "The Mansion", roster: roster)
        #expect(try SessionMessage(decoding: welcome.encoded()) == welcome)

        let update = SessionMessage.rosterUpdate(roster: roster)
        #expect(try SessionMessage(decoding: update.encoded()) == update)
    }

    @Test func bareMessagesRoundTrip() throws {
        for message in [SessionMessage.knockPending, .leave, .denied(reason: "blocked")] {
            #expect(try SessionMessage(decoding: message.encoded()) == message)
        }
    }
}
