import Foundation
import Testing

@testable import ClusterProtocol

/// 20×20 open room with border walls.
private func openRoom() -> CollisionMap {
    var solid = [Bool](repeating: false, count: 400)
    for x in 0..<20 {
        solid[x] = true
        solid[380 + x] = true
    }
    for y in 0..<20 {
        solid[y * 20] = true
        solid[y * 20 + 19] = true
    }
    return CollisionMap(width: 20, height: 20, solid: solid)
}

@Suite struct KartSimTests {
    let room = openRoom()

    func drive(
        from state: KartState, input: KartInput, seconds: Double, dt: Double = 1.0 / 60
    ) -> (state: KartState, everHitWall: Bool) {
        var current = state
        var hit = false
        for _ in 0..<Int(seconds / dt) {
            let result = KartSim.step(state: current, input: input, dt: dt, collision: room)
            current = result.state
            hit = hit || result.hitWall
        }
        return (current, hit)
    }

    @Test func acceleratesToTopSpeedAndOutrunsWalking() {
        // One second from the west side: reaches top speed well before the far wall.
        let start = KartState(position: Vec2(x: 3, y: 10))
        let (end, hit) = drive(
            from: start, input: KartInput(throttle: 1, steer: 0, drift: false), seconds: 1)
        #expect(!hit)
        #expect(abs(end.speed - KartTuning.standard.maxSpeed) < 0.1)
        #expect(end.speed > MovementRules.walkSpeed * 2)
    }

    @Test func coastingBleedsToZero() {
        var state = KartState(position: Vec2(x: 10, y: 10), speed: 8)
        (state, _) = drive(from: state, input: .coast, seconds: 3)
        #expect(state.speed == 0)
    }

    @Test func brakingStopsFasterThanCoasting() {
        let rolling = KartState(position: Vec2(x: 4, y: 10), speed: 12)
        let (coasted, _) = drive(from: rolling, input: .coast, seconds: 0.5)
        let (braked, _) = drive(
            from: rolling, input: KartInput(throttle: -1, steer: 0, drift: false), seconds: 0.5)
        #expect(braked.speed < coasted.speed)
    }

    @Test func noSteeringAtStandstill() {
        let parked = KartState(position: Vec2(x: 10, y: 10), heading: 0, speed: 0)
        let (after, _) = drive(
            from: parked, input: KartInput(throttle: 0, steer: 1, drift: false), seconds: 1)
        #expect(after.heading == 0)
    }

    @Test func steeringTurnsAndDriftTurnsHarder() {
        let rolling = KartState(position: Vec2(x: 10, y: 10), heading: 0, speed: 8)
        let dt = 1.0 / 60
        let (normal, _) = KartSim.step(
            state: rolling, input: KartInput(throttle: 0, steer: 1, drift: false), dt: dt,
            collision: room)
        let (drifting, _) = KartSim.step(
            state: rolling, input: KartInput(throttle: 0, steer: 1, drift: true), dt: dt,
            collision: room)
        #expect(normal.heading > 0)
        #expect(drifting.heading > normal.heading)
    }

    @Test func reverseGearSteersReversed() {
        let reversing = KartState(position: Vec2(x: 10, y: 10), heading: 0, speed: -2)
        let (after, _) = KartSim.step(
            state: reversing, input: KartInput(throttle: 0, steer: 1, drift: false),
            dt: 1.0 / 30, collision: room)
        #expect(after.heading < 0)
    }

    @Test func wallImpactScrubsSpeedAndReportsHit() {
        // Full speed straight at the east wall (2.4 tiles of travel reaches it).
        let charging = KartState(position: Vec2(x: 17.5, y: 10), heading: 0, speed: 12)
        let result = KartSim.step(
            state: charging, input: KartInput(throttle: 1, steer: 0, drift: false),
            dt: 0.2, collision: room)
        #expect(result.hitWall)
        #expect(result.state.speed < 12 * KartTuning.standard.wallSpeedRetention + 0.5)
        // Still inside the room.
        #expect(result.state.position.x < 19)
    }

    @Test func neverEscapesTheRoom() {
        var state = KartState(position: Vec2(x: 10, y: 10), heading: 0.7, speed: 0)
        let input = KartInput(throttle: 1, steer: 1, drift: true)
        for _ in 0..<600 {
            state = KartSim.step(state: state, input: input, dt: 1.0 / 30, collision: room).state
            #expect(state.position.x > 0 && state.position.x < 20)
            #expect(state.position.y > 0 && state.position.y < 20)
        }
    }
}

@Suite struct LerpAngleTests {
    @Test func takesTheShortWayAroundTheWrap() {
        // 170° → -170° should pass through 180°, not swing back through 0.
        let a = 170.0 * .pi / 180
        let b = -170.0 * .pi / 180
        let mid = lerpAngle(a, b, t: 0.5)
        #expect(abs(abs(mid) - .pi) < 0.01)
    }

    @Test func endpointsAndClamping() {
        #expect(lerpAngle(0.5, 1.5, t: 0) == 0.5)
        #expect(abs(lerpAngle(0.5, 1.5, t: 1) - 1.5) < 1e-9)
        #expect(lerpAngle(0, 1, t: -5) == 0)
    }
}

@Suite struct LapTrackerTests {
    // Three checkpoints in a 30-tile row; positions step through them.
    let checkpoints = [
        WorldMap.Zone(name: "cp-0", type: "checkpoint", x: 0, y: 0, width: 2, height: 2),
        WorldMap.Zone(name: "cp-1", type: "checkpoint", x: 10, y: 0, width: 2, height: 2),
        WorldMap.Zone(name: "cp-2", type: "checkpoint", x: 20, y: 0, width: 2, height: 2),
    ]

    func at(_ x: Double) -> Vec2 { Vec2(x: x, y: 1) }

    @Test func fullCircuitTimesTheLap() {
        var tracker = LapTracker()
        #expect(tracker.update(position: at(1), checkpoints: checkpoints, now: 10) == .armed)
        #expect(tracker.update(position: at(11), checkpoints: checkpoints, now: 12) == nil)
        #expect(tracker.update(position: at(21), checkpoints: checkpoints, now: 14) == nil)
        #expect(
            tracker.update(position: at(1), checkpoints: checkpoints, now: 16)
                == .lapCompleted(seconds: 6))
        // The finish crossing armed the next lap immediately.
        #expect(tracker.update(position: at(11), checkpoints: checkpoints, now: 18) == nil)
        #expect(tracker.update(position: at(21), checkpoints: checkpoints, now: 20) == nil)
        #expect(
            tracker.update(position: at(1), checkpoints: checkpoints, now: 21)
                == .lapCompleted(seconds: 5))
    }

    @Test func skippingACheckpointDoesNotCount() {
        var tracker = LapTracker()
        _ = tracker.update(position: at(1), checkpoints: checkpoints, now: 0)  // armed
        _ = tracker.update(position: at(11), checkpoints: checkpoints, now: 1)  // cp-1
        // Straight back to start, skipping cp-2: no lap.
        #expect(tracker.update(position: at(1), checkpoints: checkpoints, now: 2) == nil)
        // Complete properly afterwards — still requires cp-2 first.
        #expect(tracker.update(position: at(21), checkpoints: checkpoints, now: 3) == nil)
        #expect(
            tracker.update(position: at(1), checkpoints: checkpoints, now: 4)
                == .lapCompleted(seconds: 4))
    }

    @Test func lingeringInAZoneFiresOnce() {
        var tracker = LapTracker()
        #expect(tracker.update(position: at(0.5), checkpoints: checkpoints, now: 0) == .armed)
        #expect(tracker.update(position: at(1.0), checkpoints: checkpoints, now: 0.1) == nil)
        #expect(tracker.update(position: at(1.5), checkpoints: checkpoints, now: 0.2) == nil)
    }

    @Test func startingMidTrackDoesNotArm() {
        var tracker = LapTracker()
        #expect(tracker.update(position: at(11), checkpoints: checkpoints, now: 0) == nil)
        #expect(tracker.update(position: at(21), checkpoints: checkpoints, now: 1) == nil)
        // Reaching the line arms; it doesn't complete.
        #expect(tracker.update(position: at(1), checkpoints: checkpoints, now: 2) == .armed)
    }

    @Test func resetForgetsProgress() {
        var tracker = LapTracker()
        _ = tracker.update(position: at(1), checkpoints: checkpoints, now: 0)
        _ = tracker.update(position: at(11), checkpoints: checkpoints, now: 1)
        tracker.reset()
        #expect(tracker.update(position: at(21), checkpoints: checkpoints, now: 2) == nil)
        #expect(tracker.update(position: at(1), checkpoints: checkpoints, now: 3) == .armed)
    }
}

@Suite struct RaceCodecTests {
    @Test(arguments: [
        RaceCommand.mount(kartID: "kart-01"),
        .dismount,
        .horn,
    ])
    func commandsRoundTrip(_ command: RaceCommand) throws {
        #expect(try RaceCommand(decoding: command.encoded()) == command)
    }

    @Test func raceStateRoundTrips() throws {
        let state = RaceState(
            karts: [
                KartInfo(id: "kart-01", ownerWireID: 0xAB, x: 18, y: 26.5, heading: 1.2),
                KartInfo(id: "kart-02", ownerWireID: 0, x: 20, y: 26.5, heading: 0),
            ],
            leaderboard: [
                LapRecord(playerID: "aa", displayName: "Ricardo", timeMs: 41_250),
                LapRecord(playerID: "bb", displayName: "Dana", timeMs: 43_900),
            ])
        #expect(try RaceState(decoding: state.encoded()) == state)
        #expect(state.kart(ownedBy: 0xAB)?.id == "kart-01")
        #expect(state.kart(ownedBy: 0) == nil)
    }

    @Test func raceMessagesRideTheSession() throws {
        let messages: [SessionMessage] = [
            .raceState(RaceState()),
            .raceCommand(.mount(kartID: "kart-03")),
            .lapCompleted(timeMs: 39_990, isBest: true),
            .raceEvent(hornFrom: 0xFEED),
        ]
        for message in messages {
            #expect(try SessionMessage(decoding: message.encoded()) == message)
        }
    }

    @Test func snapshotCarriesKartModeAndHeading() throws {
        let snapshot = WorldPayload.snapshot(
            WorldSnapshot(
                tick: 7,
                players: [
                    PlayerSnapshot(
                        id: 1, x: 4, y: 5, facing: .down, isMoving: true,
                        mode: PlayerMode.kart | PlayerMode.drifting, heading: 2.1)
                ]))
        let decoded = try WorldPayload(decoding: snapshot.encoded())
        guard case .snapshot(let world) = decoded else {
            Issue.record("expected snapshot")
            return
        }
        #expect(world.players[0].isKarted)
        #expect(world.players[0].isDrifting)
        #expect(abs(world.players[0].heading - 2.1) < 0.001)
    }
}
