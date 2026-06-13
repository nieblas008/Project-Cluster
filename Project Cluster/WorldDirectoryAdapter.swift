import ClusterNet
import ClusterProtocol
import ClusterServer
import Foundation

/// Bridges the host session's people-questions to the world database, so
/// approvals, status, and last-seen survive restarts (PLAN §6, ADR 0004).
struct WorldDirectoryAdapter: HostDirectory {
    let database: WorldDatabase
    let autoApprovesUnknownPlayers = false

    func knownPlayer(id: String) throws -> KnownPlayer? {
        try database.fetchPlayer(publicKey: id).map(Self.toKnownPlayer)
    }

    func allKnownPlayers() throws -> [String: KnownPlayer] {
        var result: [String: KnownPlayer] = [:]
        for record in try database.allPlayers() {
            result[record.publicKey] = Self.toKnownPlayer(record)
        }
        return result
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

    func saveStatus(id: String, status: PlayerStatus) throws {
        try database.setStatus(publicKey: id, statusPreference: status.storageKey)
    }

    func markLeft(id: String) throws {
        try database.markSeen(publicKey: id)
    }

    private static func toKnownPlayer(_ record: PlayerRecord) -> KnownPlayer {
        KnownPlayer(
            displayName: record.displayName,
            avatarPreset: record.avatarPreset,
            status: PlayerStatus(storageKey: record.statusPreference),
            lastSeenEpoch: record.lastSeenAt?.timeIntervalSince1970 ?? 0,
            isApproved: record.isApproved,
            isBlocked: record.isBlocked
        )
    }
}
