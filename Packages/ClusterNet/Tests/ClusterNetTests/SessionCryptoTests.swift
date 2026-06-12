import CryptoKit
import Foundation
import Testing

@testable import ClusterNet

@Suite struct SessionHandshakeTests {
    @Test func bothSidesDeriveMatchingDirectionalKeys() throws {
        let hostKey = HostSessionKey()

        let (initiator, message1) = try SessionHandshake.initiate(
            responderStaticKey: hostKey.publicKeyData,
            expectedFingerprint: hostKey.fingerprint
        )
        let (hostKeys, message2) = try SessionHandshake.respond(hostKey: hostKey, message1: message1)
        let joinerKeys = try initiator.finalize(message2: message2)

        #expect(joinerKeys.transcriptHash == hostKeys.transcriptHash)

        // Joiner→host: joiner seals with sendKey, host opens with receiveKey.
        var joinerSend = SecureChannelCipher(key: joinerKeys.sendKey)
        var hostReceive = SecureChannelCipher(key: hostKeys.receiveKey)
        let sealed = try joinerSend.seal(Array("hola mansión".utf8))
        #expect(try hostReceive.open(sealed) == Array("hola mansión".utf8))

        // And the reverse direction.
        var hostSend = SecureChannelCipher(key: hostKeys.sendKey)
        var joinerReceive = SecureChannelCipher(key: joinerKeys.receiveKey)
        let sealedBack = try hostSend.seal([0x01, 0x02])
        #expect(try joinerReceive.open(sealedBack) == [0x01, 0x02])

        // Datagram keys cross-match too (ADR 0002).
        var joinerUDP = DatagramCipher(key: joinerKeys.datagramSendKey, flowID: 7)
        var hostUDP = DatagramCipher(key: hostKeys.datagramReceiveKey, flowID: 7)
        let (seq, sealedDatagram) = try joinerUDP.seal([0xFE])
        #expect(hostUDP.open(seq: seq, ciphertext: sealedDatagram) == [0xFE])
    }

    @Test func datagramCipherDropsReplaysStaleAndCrossFlow() throws {
        let key = SymmetricKey(size: .bits256)
        var sender = DatagramCipher(key: key, flowID: 3)
        var receiver = DatagramCipher(key: key, flowID: 3)

        let (seq1, packet1) = try sender.seal([1])
        let (seq2, packet2) = try sender.seal([2])
        // Out of order: newest first wins, the straggler drops.
        #expect(receiver.open(seq: seq2, ciphertext: packet2) == [2])
        #expect(receiver.open(seq: seq1, ciphertext: packet1) == nil)
        // Replay of the accepted one also drops.
        #expect(receiver.open(seq: seq2, ciphertext: packet2) == nil)

        // Same key, wrong flow AAD: refuses.
        var wrongFlow = DatagramCipher(key: key, flowID: 4)
        let (seq3, packet3) = try sender.seal([3])
        #expect(wrongFlow.open(seq: seq3, ciphertext: packet3) == nil)
    }

    @Test func wrongFingerprintRefusesToEvenStart() {
        let hostKey = HostSessionKey()
        #expect(throws: HandshakeError.authenticationFailed) {
            _ = try SessionHandshake.initiate(
                responderStaticKey: hostKey.publicKeyData,
                expectedFingerprint: Data(repeating: 0, count: 32)
            )
        }
    }

    @Test func imposterHostFailsAuthentication() throws {
        let realHost = HostSessionKey()
        let imposter = HostSessionKey()

        // Joiner pins the real host's key…
        let (initiator, message1) = try SessionHandshake.initiate(
            responderStaticKey: realHost.publicKeyData,
            expectedFingerprint: realHost.fingerprint
        )
        // …but an imposter (without the real private key) answers. Its msg1
        // check already fails — and even a forged msg2 can't authenticate.
        #expect(throws: HandshakeError.authenticationFailed) {
            _ = try SessionHandshake.respond(hostKey: imposter, message1: message1)
        }
        _ = initiator
    }

    @Test func tamperedMessage2IsRejected() throws {
        let hostKey = HostSessionKey()
        let (initiator, message1) = try SessionHandshake.initiate(
            responderStaticKey: hostKey.publicKeyData,
            expectedFingerprint: hostKey.fingerprint
        )
        var (_, message2) = try SessionHandshake.respond(hostKey: hostKey, message1: message1)
        message2[40] ^= 0xFF
        #expect(throws: HandshakeError.authenticationFailed) {
            _ = try initiator.finalize(message2: message2)
        }
    }

    @Test func garbageMessagesAreMalformedNotCrashes() throws {
        let hostKey = HostSessionKey()
        #expect(throws: HandshakeError.malformedMessage) {
            _ = try SessionHandshake.respond(hostKey: hostKey, message1: [1, 2, 3])
        }
    }
}

@Suite struct SecureChannelCipherTests {
    func makePair() throws -> (SecureChannelCipher, SecureChannelCipher) {
        let key = SymmetricKey(size: .bits256)
        return (SecureChannelCipher(key: key), SecureChannelCipher(key: key))
    }

    @Test func sealedFramesOpenInOrder() throws {
        var (sender, receiver) = try makePair()
        for i in 0..<5 {
            let sealed = try sender.seal([UInt8(i)])
            #expect(try receiver.open(sealed) == [UInt8(i)])
        }
    }

    @Test func replayedFrameFails() throws {
        var (sender, receiver) = try makePair()
        let sealed = try sender.seal([42])
        _ = try receiver.open(sealed)
        #expect(throws: HandshakeError.authenticationFailed) {
            _ = try receiver.open(sealed)  // same bytes, counter has moved on
        }
    }

    @Test func reorderedFrameFails() throws {
        var (sender, receiver) = try makePair()
        let first = try sender.seal([1])
        let second = try sender.seal([2])
        _ = first
        #expect(throws: HandshakeError.authenticationFailed) {
            _ = try receiver.open(second)  // receiver expected counter 0
        }
    }
}

@Suite struct JoinSignatureTests {
    @Test func bindsIdentityToTranscript() throws {
        let identity = PlayerIdentity.generate()
        let transcript = Data(repeating: 0x5A, count: 32)
        let signature = try JoinSignature.sign(identity: identity, transcriptHash: transcript)

        #expect(
            JoinSignature.verify(
                signature: signature, identityKey: identity.publicKeyData,
                transcriptHash: transcript))
        // Same signature presented on a different tunnel's transcript: no.
        #expect(
            !JoinSignature.verify(
                signature: signature, identityKey: identity.publicKeyData,
                transcriptHash: Data(repeating: 0x5B, count: 32)))
    }
}
