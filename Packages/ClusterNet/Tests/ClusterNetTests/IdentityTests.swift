import Foundation
import Testing

@testable import ClusterNet

@Suite struct IdentityTests {
    @Test func createsOnceThenReloadsTheSameIdentity() throws {
        let store = InMemorySecretStore()
        let first = try IdentityManager.loadOrCreate(store: store)
        let second = try IdentityManager.loadOrCreate(store: store)
        #expect(first.playerID == second.playerID)
        #expect(first.playerID.count == 64)  // 32-byte key, hex-encoded
    }

    @Test func distinctStoresYieldDistinctIdentities() throws {
        let a = try IdentityManager.loadOrCreate(store: InMemorySecretStore())
        let b = try IdentityManager.loadOrCreate(store: InMemorySecretStore())
        #expect(a.playerID != b.playerID)
    }

    @Test func signaturesVerifyAgainstThePublicKey() throws {
        let identity = try IdentityManager.loadOrCreate(store: InMemorySecretStore())
        let message = Data("join:THEMANSION:nonce123".utf8)
        let signature = try identity.sign(message)

        #expect(
            PlayerIdentity.verify(
                signature: signature, message: message, publicKey: identity.publicKeyData))
        #expect(
            !PlayerIdentity.verify(
                signature: signature, message: Data("tampered".utf8),
                publicKey: identity.publicKeyData))
    }

    @Test func corruptKeyMaterialFailsLoudly() throws {
        let store = InMemorySecretStore()
        try store.save(Data([0x01, 0x02]))
        #expect(throws: IdentityError.self) {
            _ = try IdentityManager.loadOrCreate(store: store)
        }
    }

    @Test func shortIDIsReadable() throws {
        let identity = PlayerIdentity.generate()
        #expect(identity.shortID.count == 9)
        #expect(identity.shortID.contains("-"))
    }
}
