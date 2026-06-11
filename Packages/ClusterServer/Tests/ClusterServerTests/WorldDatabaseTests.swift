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
}
