import Testing

@testable import ClusterProtocol

@Suite struct PlayerStatusTests {
    @Test func storageKeyRoundTrips() {
        for status in PlayerStatus.allCases {
            #expect(PlayerStatus(storageKey: status.storageKey) == status)
        }
    }

    @Test func unknownStorageKeyDefaultsAvailable() {
        #expect(PlayerStatus(storageKey: "garbage") == .available)
    }
}

@Suite struct PresenceRulesTests {
    @Test func awayThreshold() {
        #expect(!PresenceRules.isAway(idleSeconds: 299))
        #expect(PresenceRules.isAway(idleSeconds: 300))
        #expect(PresenceRules.isAway(idleSeconds: 10_000))
    }
}

@Suite struct RosterBuilderTests {
    func entry(
        _ id: String, _ name: String, online: Bool, away: Bool = false, lastSeen: Double = 0
    ) -> RosterEntry {
        RosterEntry(
            playerID: id, displayName: name, avatarPreset: "default", isOnline: online,
            isAway: away, lastSeenEpoch: lastSeen)
    }

    @Test func onlineBeforeOfflineActiveBeforeAway() {
        let online = [
            entry("a", "Zoe", online: true, away: true),
            entry("b", "Ana", online: true, away: false),
        ]
        let offline = [
            entry("c", "Carl", online: false, lastSeen: 100),
            entry("d", "Dora", online: false, lastSeen: 999),
        ]
        let result = RosterBuilder.build(online: online, offline: offline)
        #expect(result.map(\.playerID) == ["b", "a", "d", "c"])
        // active online first, then away online, then offline by recency.
    }

    @Test func onlineWinsWhenIDAppearsInBoth() {
        let online = [entry("x", "Live", online: true)]
        let offline = [entry("x", "Stale", online: false, lastSeen: 500)]
        let result = RosterBuilder.build(online: online, offline: offline)
        #expect(result.count == 1)
        #expect(result[0].isOnline)
        #expect(result[0].displayName == "Live")
    }

    @Test func emptyInputsProduceEmpty() {
        #expect(RosterBuilder.build(online: [], offline: []).isEmpty)
    }
}
