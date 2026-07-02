import CryptoKit
import Foundation

/// Where the private key bytes live. Production uses the Keychain; tests use memory.
public protocol SecretStore: Sendable {
    func load() throws -> Data?
    func save(_ secret: Data) throws
}

public enum IdentityError: Error {
    case keychainStatus(Int32)
    case corruptStoredKey
}

extension IdentityManager {
    /// Restores an exported identity (new Mac / reinstall) — Phase 7.
    public static func importIdentity(data: Data, store: SecretStore) throws -> PlayerIdentity {
        let identity = try PlayerIdentity(rawPrivateKey: data)
        try store.save(data)
        return identity
    }
}

public enum IdentityManager {
    /// Loads the existing identity or creates and persists a fresh one.
    /// Called once at app launch; the resulting ID is stable for this Mac forever.
    public static func loadOrCreate(store: SecretStore) throws -> PlayerIdentity {
        if let stored = try store.load() {
            guard let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: stored) else {
                throw IdentityError.corruptStoredKey
            }
            return PlayerIdentity(privateKey: key)
        }
        let identity = PlayerIdentity.generate()
        try store.save(identity.privateKey.rawRepresentation)
        return identity
    }
}

/// Test double; also handy for previews.
public final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var secret: Data?

    public init() {}

    public func load() throws -> Data? {
        lock.withLock { secret }
    }

    public func save(_ secret: Data) throws {
        lock.withLock { self.secret = secret }
    }
}

#if canImport(Security)
    import Security

    /// Generic-password Keychain item scoped to this app's sandbox.
    public struct KeychainSecretStore: SecretStore {
        public var service: String
        public var account: String

        public init(
            service: String = "com.ricardonieblas.ProjectCluster.identity",
            account: String = "primary"
        ) {
            self.service = service
            self.account = account
        }

        private var baseQuery: [String: Any] {
            [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
            ]
        }

        public func load() throws -> Data? {
            var query = baseQuery
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne

            var result: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            switch status {
            case errSecSuccess:
                return result as? Data
            case errSecItemNotFound:
                return nil
            default:
                throw IdentityError.keychainStatus(status)
            }
        }

        public func save(_ secret: Data) throws {
            var attributes = baseQuery
            attributes[kSecValueData as String] = secret
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

            let status = SecItemAdd(attributes as CFDictionary, nil)
            if status == errSecDuplicateItem {
                let update = [kSecValueData as String: secret]
                let updateStatus = SecItemUpdate(baseQuery as CFDictionary, update as CFDictionary)
                guard updateStatus == errSecSuccess else {
                    throw IdentityError.keychainStatus(updateStatus)
                }
                return
            }
            guard status == errSecSuccess else {
                throw IdentityError.keychainStatus(status)
            }
        }
    }
#endif
