import CryptoKit
import Foundation

/// A player's identity is a Curve25519 signing keypair that lives on their Mac.
/// The public key is the stable player ID the host's database keys everything
/// by (profiles, desks, lap times); the private key signs the join handshake.
/// There are no passwords because there is nothing to log into.
public struct PlayerIdentity: Sendable {
    public let privateKey: Curve25519.Signing.PrivateKey

    /// Rebuilds an identity from exported key material; throws on garbage.
    public init(rawPrivateKey: Data) throws {
        guard let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: rawPrivateKey) else {
            throw IdentityError.corruptStoredKey
        }
        self.init(privateKey: key)
    }

    public init(privateKey: Curve25519.Signing.PrivateKey) {
        self.privateKey = privateKey
    }

    public static func generate() -> PlayerIdentity {
        PlayerIdentity(privateKey: Curve25519.Signing.PrivateKey())
    }

    /// The raw private key, for the Settings export (Phase 7). Whoever holds
    /// this IS this player — the UI says so in red.
    public var exportedPrivateKey: Data {
        privateKey.rawRepresentation
    }

    public var publicKeyData: Data {
        privateKey.publicKey.rawRepresentation
    }

    /// Hex of the full public key — the database key on the host.
    public var playerID: String {
        publicKeyData.map { String(format: "%02x", $0) }.joined()
    }

    /// Short human-readable form for UI footers, e.g. "A3F0-9C2D".
    public var shortID: String {
        let hex = playerID.uppercased()
        let head = hex.prefix(8)
        return "\(head.prefix(4))-\(head.suffix(4))"
    }

    public func sign(_ message: Data) throws -> Data {
        try privateKey.signature(for: message)
    }

    public static func verify(signature: Data, message: Data, publicKey: Data) -> Bool {
        guard let key = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKey) else {
            return false
        }
        return key.isValidSignature(signature, for: message)
    }
}
