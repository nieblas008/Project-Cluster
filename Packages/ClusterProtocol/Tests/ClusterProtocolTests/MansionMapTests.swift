import Foundation
import Testing

@testable import ClusterProtocol

/// Validates the actual shipped map, not a fixture — regenerating the mansion
/// badly should fail CI, not Friday.
@Suite struct MansionMapTests {
    static var mansionURL: URL {
        // …/Packages/ClusterProtocol/Tests/ClusterProtocolTests/MansionMapTests.swift
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Project Cluster/Resources/mansion.json")
    }

    @Test func shippedMansionLoadsWithEverythingPhasesNeed() throws {
        let data = try Data(contentsOf: Self.mansionURL)
        let map = try TiledMapLoader.load(data: data)

        #expect(map.widthTiles == 44 && map.heightTiles == 30)
        #expect(!map.spawnPoints.isEmpty)

        // The spawn must be standable.
        let spawn = map.spawnPoints[0]
        #expect(
            !MovementSim.boxCollides(
                center: spawn, halfExtent: MovementRules.playerHalfExtent,
                collision: map.collision))

        // Hedge ring: the world has edges.
        #expect(map.collision.isSolid(tileX: 0, tileY: 0))
        #expect(map.collision.isSolid(tileX: 43, tileY: 29))

        // Phase 5 needs 16 desks; Phase 6 needs the track marker.
        #expect(map.zones.filter { $0.type == "desk" }.count == 16)
        #expect(map.zones.contains { $0.type == "kart-track" })

        // Desks must be reachable (inside the building, not inside walls).
        for desk in map.zones where desk.type == "desk" {
            #expect(
                !map.collision.isSolid(tileX: Int(desk.x), tileY: Int(desk.y)),
                "desk \(desk.name) is inside a wall")
        }
    }
}
