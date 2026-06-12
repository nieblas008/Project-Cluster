import ClusterProtocol
import CryptoKit
import Foundation

/// End-to-end tunnel encryption (ADR 0001): an NK-pattern handshake — the
/// initiator (joiner) knows the responder's (host's) static public key up
/// front via the fingerprint the relay forwarded. Two 48-byte messages, then
/// both sides hold directional ChaChaPoly keys the relay never saw.
///
/// Kept deliberately textbook: X25519 → HKDF chain → ChaChaPoly, with a
/// running SHA-256 transcript bound into every AEAD as associated data.
public enum HandshakeError: Error, Equatable {
    case malformedMessage
    /// DH/AEAD verification failed — wrong fingerprint, tampering, or replay.
    case authenticationFailed
}

/// The host's per-hosting-session static key. Its SHA-256 fingerprint is what
/// the relay hands to joiners; a fresh one is generated each time hosting starts.
public struct HostSessionKey: Sendable {
    let privateKey: Curve25519.KeyAgreement.PrivateKey

    public init() {
        self.privateKey = Curve25519.KeyAgreement.PrivateKey()
    }

    public var publicKeyData: Data {
        privateKey.publicKey.rawRepresentation
    }

    /// SHA-256 of the static public key — travels relay → joiner.
    public var fingerprint: Data {
        Data(SHA256.hash(data: publicKeyData))
    }
}

/// What a completed handshake yields: directional keys for the reliable
/// tunnel *and* the datagram plane (ADR 0002), plus the transcript hash that
/// identity signatures bind to (see `SessionSigning`).
public struct SessionKeys: Sendable {
    public let sendKey: SymmetricKey
    public let receiveKey: SymmetricKey
    public let datagramSendKey: SymmetricKey
    public let datagramReceiveKey: SymmetricKey
    public let transcriptHash: Data
}

public enum SessionHandshake {
    private static let protocolName = "project-cluster-nk/1"

    // MARK: Initiator (joiner)

    public struct Initiator: Sendable {
        let ephemeral: Curve25519.KeyAgreement.PrivateKey
        let chainKey: SymmetricKey
        let transcript: Data

        /// Verifies msg2, authenticating the responder against the pinned key.
        public func finalize(message2: [UInt8]) throws -> SessionKeys {
            guard message2.count == 48 else { throw HandshakeError.malformedMessage }
            let responderEphemeralData = Data(message2[0..<32])
            let tag2 = Data(message2[32..<48])

            let transcript2 = sha256(transcript + responderEphemeralData)
            guard
                let responderEphemeral = try? Curve25519.KeyAgreement.PublicKey(
                    rawRepresentation: responderEphemeralData),
                let ee = try? ephemeral.sharedSecretFromKeyAgreement(with: responderEphemeral)
            else { throw HandshakeError.malformedMessage }

            let (chainKey2, key2) = kdf(chain: chainKey, secret: ee, label: "2")
            try openEmptyBox(tag: tag2, key: key2, transcript: transcript2)

            let finalTranscript = sha256(transcript2 + tag2)
            let split = splitKeys(chain: chainKey2, transcript: finalTranscript)
            return SessionKeys(
                sendKey: split.i2r,
                receiveKey: split.r2i,
                datagramSendKey: split.udpI2R,
                datagramReceiveKey: split.udpR2I,
                transcriptHash: finalTranscript
            )
        }
    }

    /// Builds msg1 for a responder whose static public key hashes to
    /// `expectedFingerprint` (from the relay). The fingerprint *is* the pin:
    /// we receive the full key alongside it and refuse on mismatch.
    public static func initiate(
        responderStaticKey: Data, expectedFingerprint: Data
    ) throws -> (state: Initiator, message1: [UInt8]) {
        guard Data(SHA256.hash(data: responderStaticKey)) == expectedFingerprint else {
            throw HandshakeError.authenticationFailed
        }
        guard
            let responderStatic = try? Curve25519.KeyAgreement.PublicKey(
                rawRepresentation: responderStaticKey)
        else { throw HandshakeError.malformedMessage }

        let ephemeral = Curve25519.KeyAgreement.PrivateKey()
        let ephemeralPublic = ephemeral.publicKey.rawRepresentation

        let transcript0 = baseTranscript(responderStatic: responderStaticKey)
        let transcript1 = sha256(transcript0 + ephemeralPublic)

        let es = try ephemeral.sharedSecretFromKeyAgreement(with: responderStatic)
        let (chainKey1, key1) = kdf(chain: baseChainKey(), secret: es, label: "1")
        let tag1 = try sealEmptyBox(key: key1, transcript: transcript1)

        let state = Initiator(
            ephemeral: ephemeral,
            chainKey: chainKey1,
            transcript: sha256(transcript1 + tag1)
        )
        return (state, Array(ephemeralPublic + tag1))
    }

    // MARK: Responder (host)

    /// Consumes msg1, produces msg2 and the final keys in one step.
    public static func respond(
        hostKey: HostSessionKey, message1: [UInt8]
    ) throws -> (keys: SessionKeys, message2: [UInt8]) {
        guard message1.count == 48 else { throw HandshakeError.malformedMessage }
        let initiatorEphemeralData = Data(message1[0..<32])
        let tag1 = Data(message1[32..<48])

        let transcript0 = baseTranscript(responderStatic: hostKey.publicKeyData)
        let transcript1 = sha256(transcript0 + initiatorEphemeralData)

        guard
            let initiatorEphemeral = try? Curve25519.KeyAgreement.PublicKey(
                rawRepresentation: initiatorEphemeralData),
            let es = try? hostKey.privateKey.sharedSecretFromKeyAgreement(with: initiatorEphemeral)
        else { throw HandshakeError.malformedMessage }

        let (chainKey1, key1) = kdf(chain: baseChainKey(), secret: es, label: "1")
        try openEmptyBox(tag: tag1, key: key1, transcript: transcript1)
        let transcriptAfter1 = sha256(transcript1 + tag1)

        let responderEphemeral = Curve25519.KeyAgreement.PrivateKey()
        let responderEphemeralPublic = responderEphemeral.publicKey.rawRepresentation
        let transcript2 = sha256(transcriptAfter1 + responderEphemeralPublic)

        let ee = try responderEphemeral.sharedSecretFromKeyAgreement(with: initiatorEphemeral)
        let (chainKey2, key2) = kdf(chain: chainKey1, secret: ee, label: "2")
        let tag2 = try sealEmptyBox(key: key2, transcript: transcript2)

        let finalTranscript = sha256(transcript2 + tag2)
        let split = splitKeys(chain: chainKey2, transcript: finalTranscript)
        let keys = SessionKeys(
            sendKey: split.r2i,
            receiveKey: split.i2r,
            datagramSendKey: split.udpR2I,
            datagramReceiveKey: split.udpI2R,
            transcriptHash: finalTranscript
        )
        return (keys, Array(responderEphemeralPublic + tag2))
    }

    // MARK: Primitives

    private static func sha256(_ data: Data) -> Data {
        Data(SHA256.hash(data: data))
    }

    private static func baseTranscript(responderStatic: Data) -> Data {
        sha256(sha256(Data(protocolName.utf8)) + responderStatic)
    }

    private static func baseChainKey() -> SymmetricKey {
        SymmetricKey(data: sha256(Data(("ck:" + protocolName).utf8)))
    }

    private static func kdf(
        chain: SymmetricKey, secret: SharedSecret, label: String
    ) -> (chain: SymmetricKey, key: SymmetricKey) {
        let ikm = secret.withUnsafeBytes { SymmetricKey(data: Data($0)) }
        let salt = chain.withUnsafeBytes { Data($0) }
        let newChain = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: ikm, salt: salt, info: Data("ck\(label)".utf8), outputByteCount: 32)
        let key = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: ikm, salt: salt, info: Data("k\(label)".utf8), outputByteCount: 32)
        return (newChain, key)
    }

    private static func splitKeys(
        chain: SymmetricKey, transcript: Data
    ) -> (i2r: SymmetricKey, r2i: SymmetricKey, udpI2R: SymmetricKey, udpR2I: SymmetricKey) {
        func derive(_ info: String) -> SymmetricKey {
            HKDF<SHA256>.deriveKey(
                inputKeyMaterial: chain, salt: transcript, info: Data(info.utf8),
                outputByteCount: 32)
        }
        return (derive("i2r"), derive("r2i"), derive("udp-i2r"), derive("udp-r2i"))
    }

    private static let zeroNonce = try! ChaChaPoly.Nonce(data: Data(repeating: 0, count: 12))

    private static func sealEmptyBox(key: SymmetricKey, transcript: Data) throws -> Data {
        let box = try ChaChaPoly.seal(Data(), using: key, nonce: zeroNonce, authenticating: transcript)
        return box.tag
    }

    private static func openEmptyBox(tag: Data, key: SymmetricKey, transcript: Data) throws {
        guard
            let box = try? ChaChaPoly.SealedBox(nonce: zeroNonce, ciphertext: Data(), tag: tag),
            (try? ChaChaPoly.open(box, using: key, authenticating: transcript)) != nil
        else { throw HandshakeError.authenticationFailed }
    }
}

/// One direction of the established tunnel. Nonce = message counter, which the
/// reliable in-order transport guarantees; a skipped or repeated counter shows
/// up as an AEAD failure, never silent acceptance.
public struct SecureChannelCipher: Sendable {
    private let key: SymmetricKey
    private var counter: UInt64 = 0

    public init(key: SymmetricKey) {
        self.key = key
    }

    private static func nonce(for counter: UInt64) -> ChaChaPoly.Nonce {
        var data = Data(repeating: 0, count: 4)
        withUnsafeBytes(of: counter.littleEndian) { data.append(contentsOf: $0) }
        return try! ChaChaPoly.Nonce(data: data)
    }

    public mutating func seal(_ plaintext: [UInt8]) throws -> [UInt8] {
        let box = try ChaChaPoly.seal(
            Data(plaintext), using: key, nonce: Self.nonce(for: counter))
        counter += 1
        return Array(box.ciphertext + box.tag)
    }

    public mutating func open(_ sealed: [UInt8]) throws -> [UInt8] {
        guard sealed.count >= 16 else { throw HandshakeError.malformedMessage }
        let ciphertext = Data(sealed[0..<sealed.count - 16])
        let tag = Data(sealed[(sealed.count - 16)...])
        guard
            let box = try? ChaChaPoly.SealedBox(
                nonce: Self.nonce(for: counter), ciphertext: ciphertext, tag: tag),
            let plaintext = try? ChaChaPoly.open(box, using: key)
        else { throw HandshakeError.authenticationFailed }
        counter += 1
        return Array(plaintext)
    }
}

/// Binds a player identity to a specific tunnel: signature over the join
/// context + the handshake transcript hash. Can't be replayed onto any other
/// session because the transcript is unique per handshake.
public enum JoinSignature {
    public static func message(transcriptHash: Data) -> Data {
        Data(SessionSigning.joinContext.utf8) + transcriptHash
    }

    public static func sign(identity: PlayerIdentity, transcriptHash: Data) throws -> Data {
        try identity.sign(message(transcriptHash: transcriptHash))
    }

    public static func verify(signature: Data, identityKey: Data, transcriptHash: Data) -> Bool {
        PlayerIdentity.verify(
            signature: signature,
            message: message(transcriptHash: transcriptHash),
            publicKey: identityKey
        )
    }
}
