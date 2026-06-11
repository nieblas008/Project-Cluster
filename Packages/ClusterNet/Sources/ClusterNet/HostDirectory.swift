import Foundation

/// What the host session needs to know about people, without depending on the
/// world database directly (the app adapts `WorldDatabase` to this; tests and
/// the smoke harness use the in-memory version).
public struct KnownPlayer: Equatable, Sendable {
    public var displayName: String
    public var isApproved: Bool
    public var isBlocked: Bool

    public init(displayName: String, isApproved: Bool, isBlocked: Bool) {
        self.displayName = displayName
        self.isApproved = isApproved
        self.isBlocked = isBlocked
    }
}

public protocol HostDirectory: Sendable {
    /// True skips the knock for never-seen identities (smoke tests only).
    var autoApprovesUnknownPlayers: Bool { get }
    func knownPlayer(id: String) throws -> KnownPlayer?
    /// Called when a player is admitted: persist + mark approved + seen.
    func recordJoin(id: String, displayName: String, avatarPreset: String) throws
    func markLeft(id: String) throws
}

public final class InMemoryDirectory: HostDirectory, @unchecked Sendable {
    private let lock = NSLock()
    private var players: [String: KnownPlayer] = [:]
    public let autoApprovesUnknownPlayers: Bool

    public init(autoApprove: Bool = false) {
        self.autoApprovesUnknownPlayers = autoApprove
    }

    public func knownPlayer(id: String) throws -> KnownPlayer? {
        lock.withLock { players[id] }
    }

    public func recordJoin(id: String, displayName: String, avatarPreset: String) throws {
        lock.withLock {
            players[id] = KnownPlayer(displayName: displayName, isApproved: true, isBlocked: false)
        }
    }

    public func markLeft(id: String) throws {}
}
