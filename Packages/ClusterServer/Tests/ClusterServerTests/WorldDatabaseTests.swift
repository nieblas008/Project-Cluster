import Foundation
import Testing

@testable import ClusterServer

@Suite struct WorldDatabaseTests {
    func makeDatabase() throws -> WorldDatabase {
        try WorldDatabase(fileURL: nil)  // in-memory
    }

    @Test func migrationCreatesASingletonSpaceOnce() throws {
        let db = try makeDatabase()
        let first = try db.ensureSpace(named: "The Mansion")
        let second = try db.ensureSpace(named: "Renamed Later")

        #expect(first.id == 1)
        #expect(first.name == "The Mansion")
        #expect(second == first)  // second call returns, never recreates
        #expect(first.inviteSecret.count == 12)
    }

    @Test func inviteSecretsUseUnambiguousAlphabet() {
        let secret = WorldDatabase.makeInviteSecret(length: 200)
        let forbidden: Set<Character> = ["0", "O", "1", "I", "L"]
        #expect(secret.allSatisfy { !forbidden.contains($0) })
    }

    @Test func playersPersistAndUpdate() throws {
        let db = try makeDatabase()
        let key = String(repeating: "ab", count: 32)
        try db.upsertPlayer(
            PlayerRecord(publicKey: key, displayName: "Dana", isApproved: true))

        let loaded = try #require(try db.fetchPlayer(publicKey: key))
        #expect(loaded.displayName == "Dana")
        #expect(loaded.isApproved)
        #expect(loaded.lastSeenAt == nil)

        let seen = Date(timeIntervalSince1970: 1_750_000_000)
        try db.markSeen(publicKey: key, at: seen)
        let seenPlayer = try #require(try db.fetchPlayer(publicKey: key))
        #expect(abs(seenPlayer.lastSeenAt!.timeIntervalSince(seen)) < 1)

        #expect(try db.playerCount() == 1)
    }

    @Test func unknownPlayersAreNil() throws {
        let db = try makeDatabase()
        #expect(try db.fetchPlayer(publicKey: "nope") == nil)
    }

    @Test func deskClaimsPersistAndRelease() throws {
        let db = try makeDatabase()
        try db.setDeskClaim(zone: "desk-01", ownerID: "ricardo")
        try db.setDeskClaim(zone: "desk-02", ownerID: "dana")
        #expect(try db.allDeskClaims().count == 2)

        // Re-claim overwrites; release deletes the row.
        try db.setDeskClaim(zone: "desk-01", ownerID: "someone-else")
        #expect(
            try db.allDeskClaims().first { $0.zone == "desk-01" }?.ownerID == "someone-else")
        try db.setDeskClaim(zone: "desk-01", ownerID: "")
        #expect(try db.allDeskClaims().map(\.zone) == ["desk-02"])
    }

    @Test func deskItemsGetStableIDsAndMutate() throws {
        let db = try makeDatabase()
        let first = try db.insertDeskItem(zone: "desk-01", catalogID: 5, x: 10, y: 12, rotation: 0)
        let second = try db.insertDeskItem(zone: "desk-01", catalogID: 16, x: 10.5, y: 12, rotation: 1)
        #expect(second > first)  // monotonic host-assigned handles

        try db.moveDeskItem(id: first, x: 11, y: 12.5, rotation: 2)
        let items = try db.allDeskItems()
        #expect(items.count == 2)
        #expect(items[0].x == 11 && items[0].rotation == 2)

        try db.removeDeskItem(id: second)
        #expect(try db.allDeskItems().count == 1)

        try db.clearDeskItems(zone: "desk-01")
        #expect(try db.allDeskItems().isEmpty)
    }

    @Test func lapTimesKeepPersonalBests() throws {
        let db = try makeDatabase()
        try db.insertLapTime(playerID: "aa", displayName: "Ricardo", timeMs: 45_000)
        try db.insertLapTime(playerID: "aa", displayName: "Ricardo", timeMs: 41_500)
        try db.insertLapTime(playerID: "aa", displayName: "Ricardo", timeMs: 48_000)
        try db.insertLapTime(playerID: "bb", displayName: "Dana", timeMs: 43_000)

        #expect(try db.bestLap(playerID: "aa") == 41_500)
        #expect(try db.bestLap(playerID: "nobody") == nil)

        let board = try db.bestLapTimes(limit: 10)
        #expect(board.count == 2)
        #expect(board[0].playerID == "aa" && board[0].timeMs == 41_500)
        #expect(board[1].playerID == "bb" && board[1].timeMs == 43_000)

        // Limit respected.
        #expect(try db.bestLapTimes(limit: 1).count == 1)
    }

    @Test func exportedCopyOpensIntact() throws {
        // The restore drill in file form: copy the file, open the copy,
        // everything is there (docs/runbooks/restore.md).
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let original = dir.appendingPathComponent("world.sqlite")
        let backup = dir.appendingPathComponent("backup.sqlite")

        let db = try WorldDatabase(fileURL: original)
        _ = try db.ensureSpace(named: "The Mansion")
        try db.upsertPlayer(
            PlayerRecord(publicKey: "aa", displayName: "Ricardo", isApproved: true))
        try db.setDeskClaim(zone: "desk-01", ownerID: "aa")
        try db.insertLapTime(playerID: "aa", displayName: "Ricardo", timeMs: 42_000)

        try FileManager.default.copyItem(at: original, to: backup)
        let restored = try WorldDatabase(fileURL: backup)
        #expect(try restored.fetchPlayer(publicKey: "aa")?.displayName == "Ricardo")
        #expect(try restored.allDeskClaims().map(\.zone) == ["desk-01"])
        #expect(try restored.bestLap(playerID: "aa") == 42_000)
        try? FileManager.default.removeItem(at: dir)
    }
}
