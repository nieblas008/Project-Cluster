import ClusterNet
import ClusterServer
import Foundation

/// Bridges the host session's people-questions to the world database, so
/// approvals and last-seen survive restarts (PLAN §6).
struct WorldDirectoryAdapter: HostDirectory {
    let database: WorldDatabase
    let autoApprovesUnknownPlayers = false

    func knownPlayer(id: String) throws -> KnownPlayer? {
        guard let record = try database.fetchPlayer(publicKey: id) else { return nil }
        return KnownPlayer(
            displayName: record.displayName,
            isApproved: record.isApproved,
            isBlocked: record.isBlocked
        )
    }

    func recordJoin(id: String, displayName: String, avatarPreset: String) throws {
        var record =
            try database.fetchPlayer(publicKey: id)
            ?? PlayerRecord(publicKey: id, displayName: displayName)
        record.displayName = displayName
        record.avatarPreset = avatarPreset
        record.isApproved = true
        record.lastSeenAt = Date()
        try database.upsertPlayer(record)
    }

    func markLeft(id: String) throws {
        try database.markSeen(publicKey: id)
    }
}
