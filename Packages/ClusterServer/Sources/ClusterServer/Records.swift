import Foundation
import GRDB

/// A player the host's world has met, keyed by the public key of their identity.
/// Created on first knock; survives across sessions so desks, lap times, and
/// last-seen stick to people.
public struct PlayerRecord: Codable, Equatable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "players"

    /// Hex-encoded Curve25519 public key — see `PlayerIdentity.playerID`.
    public var publicKey: String
    public var displayName: String
    public var avatarPreset: String
    /// Persisted status preference: "available" | "focus" | "dnd".
    public var statusPreference: String
    public var lastSeenAt: Date?
    public var isApproved: Bool
    public var isBlocked: Bool

    public init(
        publicKey: String,
        displayName: String,
        avatarPreset: String = "default",
        statusPreference: String = "available",
        lastSeenAt: Date? = nil,
        isApproved: Bool = false,
        isBlocked: Bool = false
    ) {
        self.publicKey = publicKey
        self.displayName = displayName
        self.avatarPreset = avatarPreset
        self.statusPreference = statusPreference
        self.lastSeenAt = lastSeenAt
        self.isApproved = isApproved
        self.isBlocked = isBlocked
    }
}

/// The single world this Mac hosts. Always row id = 1 — multi-space is a
/// product question for another year.
public struct SpaceRecord: Codable, Equatable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "space"

    public var id: Int64
    public var name: String
    public var mapVersion: String
    /// Rotatable secret embedded in session codes; gates joining.
    public var inviteSecret: String
    public var createdAt: Date

    public init(id: Int64 = 1, name: String, mapVersion: String, inviteSecret: String, createdAt: Date) {
        self.id = id
        self.name = name
        self.mapVersion = mapVersion
        self.inviteSecret = inviteSecret
        self.createdAt = createdAt
    }
}
