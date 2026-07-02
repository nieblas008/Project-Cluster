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
}
