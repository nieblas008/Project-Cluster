import Foundation
import GRDB

/// The host's world: one SQLite file under Application Support. Positions and
/// kart claims never come near this database — it holds only durable state.
public final class WorldDatabase: Sendable {
    private let dbQueue: DatabaseQueue
    /// Nil for in-memory databases (tests, previews).
    public let fileURL: URL?

    /// `~/Library/Application Support/Project Cluster/world.sqlite`
    /// (inside the sandbox container when sandboxed — Time Machine covers it).
    public static func defaultFileURL() throws -> URL {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return
            support
            .appendingPathComponent("Project Cluster", isDirectory: true)
            .appendingPathComponent("world.sqlite")
    }

    /// Pass nil to get an in-memory database.
    public init(fileURL: URL?) throws {
        self.fileURL = fileURL
        if let fileURL {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            self.dbQueue = try DatabaseQueue(path: fileURL.path)
        } else {
            self.dbQueue = try DatabaseQueue()
        }
        try Self.migrator.migrate(dbQueue)
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1-players-and-space") { db in
            try db.create(table: PlayerRecord.databaseTableName) { t in
                t.primaryKey("publicKey", .text)
                t.column("displayName", .text).notNull()
                t.column("avatarPreset", .text).notNull()
                t.column("statusPreference", .text).notNull()
                t.column("lastSeenAt", .datetime)
                t.column("isApproved", .boolean).notNull().defaults(to: false)
                t.column("isBlocked", .boolean).notNull().defaults(to: false)
            }

            try db.create(table: SpaceRecord.databaseTableName) { t in
                t.primaryKey("id", .integer)
                t.column("name", .text).notNull()
                t.column("mapVersion", .text).notNull()
                t.column("inviteSecret", .text).notNull()
                t.column("createdAt", .datetime).notNull()
                t.check(sql: "id = 1")
            }
        }

        return migrator
    }

    // MARK: - Space

    /// Returns the world row, creating it with a fresh invite secret on first run.
    public func ensureSpace(named name: String) throws -> SpaceRecord {
        try dbQueue.write { db in
            if let existing = try SpaceRecord.fetchOne(db, key: 1) {
                return existing
            }
            let space = SpaceRecord(
                name: name,
                mapVersion: "none",
                inviteSecret: Self.makeInviteSecret(),
                createdAt: Date()
            )
            try space.insert(db)
            // Return the stored row, not the in-memory value: SQLite truncates
            // Date precision, and callers must see exactly what future reads see.
            return try SpaceRecord.fetchOne(db, key: 1)!
        }
    }

    /// Unambiguous alphabet (no 0/O, 1/I/L) — these get read aloud on calls.
    static func makeInviteSecret(length: Int = 12) -> String {
        let alphabet = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")
        return String((0..<length).map { _ in alphabet.randomElement()! })
    }

    // MARK: - Players

    public func upsertPlayer(_ player: PlayerRecord) throws {
        try dbQueue.write { db in
            try player.save(db)
        }
    }

    public func fetchPlayer(publicKey: String) throws -> PlayerRecord? {
        try dbQueue.read { db in
            try PlayerRecord.fetchOne(db, key: publicKey)
        }
    }

    public func markSeen(publicKey: String, at date: Date = Date()) throws {
        try dbQueue.write { db in
            if var player = try PlayerRecord.fetchOne(db, key: publicKey) {
                player.lastSeenAt = date
                try player.update(db)
            }
        }
    }

    public func playerCount() throws -> Int {
        try dbQueue.read { db in
            try PlayerRecord.fetchCount(db)
        }
    }

    public func allPlayers() throws -> [PlayerRecord] {
        try dbQueue.read { db in
            try PlayerRecord.fetchAll(db)
        }
    }

    public func setStatus(publicKey: String, statusPreference: String) throws {
        try dbQueue.write { db in
            if var player = try PlayerRecord.fetchOne(db, key: publicKey) {
                player.statusPreference = statusPreference
                try player.update(db)
            }
        }
    }
}
