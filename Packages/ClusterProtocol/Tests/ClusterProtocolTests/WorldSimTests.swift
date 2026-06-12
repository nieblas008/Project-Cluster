import Foundation
import Testing

@testable import ClusterProtocol

/// 10×10 room with solid border walls.
private func walledRoom() -> CollisionMap {
    var solid = [Bool](repeating: false, count: 100)
    for i in 0..<10 {
        solid[i] = true  // top row
        solid[90 + i] = true  // bottom row
        solid[i * 10] = true  // left column
        solid[i * 10 + 9] = true  // right column
    }
    return CollisionMap(width: 10, height: 10, solid: solid)
}

@Suite struct MovementSimTests {
    let room = walledRoom()

    @Test func walksFreelyInOpenSpace() {
        let start = Vec2(x: 5, y: 5)
        let end = MovementSim.step(
            position: start, input: MoveInput(dirX: 1, dirY: 0), dt: 0.1, collision: room)
        #expect(abs(end.x - (5 + MovementRules.walkSpeed * 0.1)) < 1e-9)
        #expect(end.y == 5)
    }

    @Test func diagonalIsNotFaster() {
        let start = Vec2(x: 5, y: 5)
        let end = MovementSim.step(
            position: start, input: MoveInput(dirX: 1, dirY: 1), dt: 0.1, collision: room)
        #expect(start.distance(to: end) <= MovementRules.walkSpeed * 0.1 + 1e-9)
    }

    @Test func wallsStopMovementFlush() {
        // Sprint right repeatedly: must stop just before the wall at x=9.
        var pos = Vec2(x: 5, y: 5)
        for _ in 0..<100 {
            pos = MovementSim.step(
                position: pos, input: MoveInput(dirX: 1, dirY: 0), dt: 0.05, collision: room)
        }
        #expect(pos.x < 9 - MovementRules.playerHalfExtent + 0.01)
        #expect(pos.x > 8)  // got close, didn't bounce away
        #expect(pos.y == 5)
    }

    @Test func slidesAlongWallsOnDiagonal() {
        // Pushing up-right against the right wall should still move up.
        var pos = Vec2(x: 8.6, y: 5)
        pos = MovementSim.step(
            position: pos, input: MoveInput(dirX: 1, dirY: -1), dt: 0.1, collision: room)
        #expect(pos.y < 5)
    }

    @Test func idleInputDoesNothing() {
        let start = Vec2(x: 3, y: 3)
        #expect(MovementSim.step(position: start, input: .idle, dt: 0.1, collision: room) == start)
    }
}

@Suite struct MovementValidationTests {
    let room = walledRoom()

    @Test func acceptsPlausibleMovement() {
        let previous = Vec2(x: 5, y: 5)
        let proposed = Vec2(x: 5.2, y: 5)
        let accepted = MovementSim.validate(
            previous: previous, proposed: proposed, dt: 1.0 / 15, collision: room)
        #expect(accepted == proposed)
    }

    @Test func clampsTeleports() {
        let previous = Vec2(x: 5, y: 5)
        let proposed = Vec2(x: 8.5, y: 5)  // way beyond one tick of walking
        let accepted = MovementSim.validate(
            previous: previous, proposed: proposed, dt: 1.0 / 15, collision: room)
        let maxLegal = MovementRules.walkSpeed * (1.0 / 15) * MovementRules.validationSpeedSlack
        #expect(previous.distance(to: accepted) <= maxLegal + 1e-9)
    }

    @Test func refusesWallClips() {
        let previous = Vec2(x: 8.5, y: 5)
        let proposed = Vec2(x: 9.0, y: 5)  // inside the wall tile
        let accepted = MovementSim.validate(
            previous: previous, proposed: proposed, dt: 1.0 / 15, collision: room)
        #expect(accepted == previous)
    }

    @Test func facingFollowsDominantAxis() {
        #expect(Facing.from(input: MoveInput(dirX: 1, dirY: 0), previous: .down) == .right)
        #expect(Facing.from(input: MoveInput(dirX: 0, dirY: -1), previous: .down) == .up)
        #expect(Facing.from(input: .idle, previous: .left) == .left)
    }
}

@Suite struct TiledMapLoaderTests {
    /// Minimal valid map: 3×2, one wall tile (gid 2 collides), one spawn.
    private var sampleJSON: Data {
        let json = """
            {
              "width": 3, "height": 2, "tilewidth": 32,
              "layers": [
                {"name": "floor", "type": "tilelayer", "data": [1,1,1,1,1,1]},
                {"name": "walls", "type": "tilelayer", "data": [2,0,0,0,0,2]},
                {"name": "objects", "type": "objectgroup", "objects": [
                  {"name": "spawn", "type": "spawn", "x": 48.0, "y": 32.0},
                  {"name": "desk-01", "type": "desk", "x": 64.0, "y": 0.0, "width": 32.0, "height": 32.0}
                ]}
              ],
              "tilesets": [{
                "firstgid": 1,
                "tiles": [{"id": 1, "properties": [{"name": "collides", "type": "bool", "value": true}]}]
              }]
            }
            """
        return Data(json.utf8)
    }

    @Test func loadsCollisionSpawnsAndZones() throws {
        let map = try TiledMapLoader.load(data: sampleJSON)
        #expect(map.widthTiles == 3 && map.heightTiles == 2)
        #expect(map.collision.isSolid(tileX: 0, tileY: 0))  // gid 2 = local id 1 = collides
        #expect(!map.collision.isSolid(tileX: 1, tileY: 0))
        #expect(map.collision.isSolid(tileX: 2, tileY: 1))
        #expect(map.collision.isSolid(tileX: -1, tileY: 0))  // OOB solid
        #expect(map.spawnPoints == [Vec2(x: 1.5, y: 1.0)])
        #expect(map.zones.count == 1)
        #expect(map.zones[0].type == "desk")
        #expect(map.contentHash.count == 16)
    }

    @Test func missingSpawnFails() {
        let json = """
            {"width":1,"height":1,"tilewidth":32,
             "layers":[{"name":"floor","type":"tilelayer","data":[1]},
                       {"name":"walls","type":"tilelayer","data":[0]}],
             "tilesets":[{"firstgid":1}]}
            """
        #expect(throws: WorldMapError.noSpawnPoints) {
            _ = try TiledMapLoader.load(data: Data(json.utf8))
        }
    }
}

@Suite struct WorldWireTests {
    @Test func payloadsRoundTrip() throws {
        let input = WorldPayload.input(
            InputFrame(seq: 77, input: MoveInput(dirX: -1, dirY: 1), x: 4.25, y: 9.5))
        #expect(try WorldPayload(decoding: input.encoded()) == input)

        let snapshot = WorldPayload.snapshot(
            WorldSnapshot(
                tick: 900,
                players: [
                    PlayerSnapshot(id: 0xAB12, x: 1, y: 2, facing: .left, isMoving: true),
                    PlayerSnapshot(id: 0xCD34, x: 8.5, y: 3.25, facing: .down, isMoving: false),
                ]))
        #expect(try WorldPayload(decoding: snapshot.encoded()) == snapshot)
    }

    @Test func wireIDPrefixIsStable() {
        let hex = "a1b2c3d4e5f60718" + String(repeating: "0", count: 48)
        #expect(PlayerWireID.prefix(fromHexID: hex) == 0xA1B2_C3D4_E5F6_0718)
    }

    @Test func datagramLayoutsRoundTrip() {
        let bind = DatagramWire.encodeBind(flowID: 12, token: 999)
        let decoded = DatagramWire.decodeBind(bind)
        #expect(decoded?.flowID == 12 && decoded?.token == 999)
        #expect(DatagramWire.peekFlowID(bind) == nil)  // binds are not data

        let data = DatagramWire.encodeData(flowID: 12, seq: 5, ciphertext: [9, 9, 9, 9, 9])
        #expect(DatagramWire.peekFlowID(data) == 12)
        let parsed = DatagramWire.decodeData(data)
        #expect(parsed?.seq == 5 && parsed?.ciphertext == [9, 9, 9, 9, 9])
    }

    @Test func interpolatorLerpsBetweenSamplesAndClamps() {
        var interp = RemotePlayerInterpolator()
        interp.record(PlayerSnapshot(id: 1, x: 0, y: 0, facing: .right, isMoving: true), at: 10.0)
        interp.record(PlayerSnapshot(id: 1, x: 2, y: 0, facing: .right, isMoving: true), at: 10.2)

        let mid = interp.sample(at: 10.1)
        #expect(abs(Double(mid!.x) - 1.0) < 1e-6)
        #expect(interp.sample(at: 9.0)!.x == 0)  // clamp start
        #expect(interp.sample(at: 11.0)!.x == 2)  // clamp end, no extrapolation
    }
}
