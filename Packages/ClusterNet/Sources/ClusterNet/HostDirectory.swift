import ClusterProtocol
import Foundation

/// What the host session needs to know about people, without depending on the
/// world database directly (the app adapts `WorldDatabase` to this; tests and
/// the smoke harness use the in-memory version).
public struct KnownPlayer: Equatable, Sendable {
    public var displayName: String
    public var avatarPreset: String
    public var status: PlayerStatus
    public var lastSeenEpoch: Double
    public var isApproved: Bool
    public var isBlocked: Bool

    public init(
        displayName: String,
        avatarPreset: String = "default",
        status: PlayerStatus = .available,
        lastSeenEpoch: Double = 0,
        isApproved: Bool,
        isBlocked: Bool
    ) {
        self.displayName = displayName
        self.avatarPreset = avatarPreset
        self.status = status
        self.lastSeenEpoch = lastSeenEpoch
        self.isApproved = isApproved
        self.isBlocked = isBlocked
    }
}

public protocol HostDirectory: Sendable {
    /// True skips the knock for never-seen identities (smoke tests only).
    var autoApprovesUnknownPlayers: Bool { get }
    func knownPlayer(id: String) throws -> KnownPlayer?
    /// Every player this world has ever admitted — for the offline roster rows.
    func allKnownPlayers() throws -> [String: KnownPlayer]
    /// Called when a player is admitted: persist + mark approved + seen.
    func recordJoin(id: String, displayName: String, avatarPreset: String) throws
    /// Persist a status preference so it survives across sessions.
    func saveStatus(id: String, status: PlayerStatus) throws
    /// Blocklist (Phase 7): a blocked identity is refused at the door.
    func setBlocked(id: String, blocked: Bool) throws
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

    public func allKnownPlayers() throws -> [String: KnownPlayer] {
        lock.withLock { players }
    }

    public func recordJoin(id: String, displayName: String, avatarPreset: String) throws {
        lock.withLock {
            let existing = players[id]
            players[id] = KnownPlayer(
                displayName: displayName,
                avatarPreset: avatarPreset,
                status: existing?.status ?? .available,
                lastSeenEpoch: existing?.lastSeenEpoch ?? 0,
                isApproved: true,
                isBlocked: existing?.isBlocked ?? false
            )
        }
    }

    public func saveStatus(id: String, status: PlayerStatus) throws {
        lock.withLock {
            if var player = players[id] {
                player.status = status
                players[id] = player
            }
        }
    }

    public func setBlocked(id: String, blocked: Bool) throws {
        lock.withLock {
            if var player = players[id] {
                player.isBlocked = blocked
                players[id] = player
            }
        }
    }

    public func markLeft(id: String) throws {
        lock.withLock {
            if var player = players[id] {
                player.lastSeenEpoch = Date().timeIntervalSince1970
                players[id] = player
            }
        }
    }
}
