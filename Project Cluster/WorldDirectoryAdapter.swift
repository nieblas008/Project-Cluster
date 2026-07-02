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

/// Desk persistence over the world database (ADR 0005).
struct WorldDeskStoreAdapter: DeskStore {
    let database: WorldDatabase

    func loadDeskState() throws -> DeskState {
        DeskState(
            claims: try database.allDeskClaims().map {
                DeskClaim(zone: $0.zone, ownerID: $0.ownerID)
            },
            items: try database.allDeskItems().compactMap { record in
                guard let id = record.id else { return nil }
                return PlacedItem(
                    id: UInt32(id), zone: record.zone, catalogID: UInt16(record.catalogID),
                    x: Float(record.x), y: Float(record.y), rotation: UInt8(record.rotation))
            })
    }

    func setClaim(zone: String, ownerID: String) throws {
        try database.setDeskClaim(zone: zone, ownerID: ownerID)
    }

    func clearItems(zone: String) throws {
        try database.clearDeskItems(zone: zone)
    }

    func insertItem(zone: String, catalogID: UInt16, x: Float, y: Float, rotation: UInt8) throws
        -> UInt32
    {
        UInt32(
            try database.insertDeskItem(
                zone: zone, catalogID: Int(catalogID), x: Double(x), y: Double(y),
                rotation: Int(rotation)))
    }

    func removeItem(id: UInt32) throws {
        try database.removeDeskItem(id: Int64(id))
    }

    func moveItem(id: UInt32, x: Float, y: Float, rotation: UInt8) throws {
        try database.moveDeskItem(
            id: Int64(id), x: Double(x), y: Double(y), rotation: Int(rotation))
    }
}

/// Lap persistence over the world database (ADR 0006).
struct WorldLapStoreAdapter: LapStore {
    let database: WorldDatabase

    func insertLap(playerID: String, displayName: String, timeMs: Int) throws {
        try database.insertLapTime(playerID: playerID, displayName: displayName, timeMs: timeMs)
    }

    func bestLap(playerID: String) throws -> Int? {
        try database.bestLap(playerID: playerID)
    }

    func topLaps(limit: Int) throws -> [LapRecord] {
        try database.bestLapTimes(limit: limit).map {
            LapRecord(
                playerID: $0.playerID, displayName: $0.displayName, timeMs: UInt32($0.timeMs))
        }
    }
}
