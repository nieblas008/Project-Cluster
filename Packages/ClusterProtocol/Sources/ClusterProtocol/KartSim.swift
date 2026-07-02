import Foundation

/// A karted player's motion state. Heading is radians in tile space
/// (y grows downward): 0 = east, π/2 = south.
public struct KartState: Equatable, Sendable {
    public var position: Vec2
    public var heading: Double
    /// Tiles/s along the heading; negative = reverse.
    public var speed: Double

    public init(position: Vec2, heading: Double = 0, speed: Double = 0) {
        self.position = position
        self.heading = heading
        self.speed = speed
    }
}

/// Driver intent, derived from the same keys as walking plus the handbrake.
public struct KartInput: Equatable, Sendable {
    /// +1 accelerate, -1 brake/reverse, 0 coast.
    public var throttle: Int8
    /// -1 left, +1 right (screen sense).
    public var steer: Int8
    public var drift: Bool

    public init(throttle: Int8, steer: Int8, drift: Bool) {
        self.throttle = throttle
        self.steer = steer
        self.drift = drift
    }

    /// W/↑ = forward, S/↓ = brake/reverse, A/D = steer.
    public init(moveInput: MoveInput, drift: Bool) {
        self.throttle = -moveInput.dirY
        self.steer = moveInput.dirX
        self.drift = drift
    }

    public static let coast = KartInput(throttle: 0, steer: 0, drift: false)
}

/// Arcade kart kinematics (ADR 0006): velocity always along the heading, drift
/// = more steering + more drag, walls scrub speed. Pure — the same step runs
/// as prediction and validation context on both ends.
public enum KartSim {
    /// One integration step. `hitWall` is transient (SFX/feel, not state).
    public static func step(
        state: KartState, input: KartInput, dt: Double,
        tuning: KartTuning = .standard, collision: CollisionMap
    ) -> (state: KartState, hitWall: Bool) {
        var next = state

        // Speed along the heading.
        switch input.throttle {
        case 1:
            next.speed = min(next.speed + tuning.acceleration * dt, tuning.maxSpeed)
        case -1:
            if next.speed > 0 {
                next.speed = max(next.speed - tuning.braking * dt, 0)
            } else {
                next.speed = max(next.speed - tuning.acceleration * 0.6 * dt, -tuning.maxReverseSpeed)
            }
        default:
            let drag = tuning.coastDrag * (input.drift ? 2 : 1) * dt
            next.speed = next.speed > 0 ? max(next.speed - drag, 0) : min(next.speed + drag, 0)
        }
        if input.drift, next.speed > 0 {
            // The handbrake itself bleeds speed even under throttle.
            next.speed = max(next.speed - tuning.coastDrag * dt, 0)
        }

        // Steering: none at standstill, full above a quarter of top speed,
        // reversed in reverse gear, boosted while drifting.
        let steerFactor = min(abs(next.speed) / (tuning.maxSpeed * 0.25), 1)
        let driftBoost = input.drift ? tuning.driftTurnBoost : 1
        let direction: Double = next.speed >= 0 ? 1 : -1
        next.heading += Double(input.steer) * tuning.turnRate * steerFactor * driftBoost * direction * dt

        // Advance with axis-separated slide; a blocked axis scrubs speed.
        let dx = cos(next.heading) * next.speed * dt
        let dy = sin(next.heading) * next.speed * dt
        let intended = Vec2(x: next.position.x + dx, y: next.position.y + dy)
        var moved = next.position
        moved.x = slideAxis(from: moved, delta: dx, axis: .x, tuning: tuning, collision: collision)
        moved.y = slideAxis(from: moved, delta: dy, axis: .y, tuning: tuning, collision: collision)

        let hitWall =
            abs(moved.x - intended.x) > 0.001 || abs(moved.y - intended.y) > 0.001
        if hitWall {
            next.speed *= tuning.wallSpeedRetention
        }
        if abs(next.speed) < 0.05 && input.throttle == 0 {
            next.speed = 0
        }
        next.position = moved
        return (next, hitWall)
    }

    private enum Axis { case x, y }

    private static func slideAxis(
        from position: Vec2, delta: Double, axis: Axis, tuning: KartTuning,
        collision: CollisionMap
    ) -> Double {
        let he = tuning.halfExtent
        let epsilon = 0.001
        var candidate = position
        switch axis {
        case .x: candidate.x += delta
        case .y: candidate.y += delta
        }
        if !MovementSim.boxCollides(center: candidate, halfExtent: he, collision: collision) {
            return axis == .x ? candidate.x : candidate.y
        }
        var clamped: Double
        switch axis {
        case .x:
            clamped =
                delta > 0
                ? (candidate.x + he).rounded(.down) - he - epsilon
                : (candidate.x - he).rounded(.up) + he + epsilon
            candidate.x = clamped
        case .y:
            clamped =
                delta > 0
                ? (candidate.y + he).rounded(.down) - he - epsilon
                : (candidate.y - he).rounded(.up) + he + epsilon
            candidate.y = clamped
        }
        if MovementSim.boxCollides(center: candidate, halfExtent: he, collision: collision) {
            return axis == .x ? position.x : position.y
        }
        return clamped
    }
}

/// Interpolates the short way around the circle — remote karts turn smoothly
/// through the ±π wrap.
public func lerpAngle(_ a: Double, _ b: Double, t: Double) -> Double {
    var delta = (b - a).truncatingRemainder(dividingBy: 2 * .pi)
    if delta > .pi { delta -= 2 * .pi }
    if delta < -.pi { delta += 2 * .pi }
    return a + delta * min(max(t, 0), 1)
}

/// Order-enforced lap timing (ADR 0006): arm at the start line, visit every
/// checkpoint in sequence, complete crossing the start line again. Pure — the
/// host runs one per karted player on validated positions and its own clock.
public struct LapTracker: Equatable, Sendable {
    public enum Event: Equatable, Sendable {
        case armed
        case lapCompleted(seconds: Double)
    }

    private var expected: Int?
    private var lapStart: Double?

    public init() {}

    public mutating func reset() {
        expected = nil
        lapStart = nil
    }

    /// `checkpoints` must be ordered (cp-0 first) and non-empty.
    public mutating func update(
        position: Vec2, checkpoints: [WorldMap.Zone], now: Double
    ) -> Event? {
        guard !checkpoints.isEmpty,
            let inside = checkpoints.firstIndex(where: {
                DeskRules.isInside(x: position.x, y: position.y, zone: $0)
            })
        else { return nil }

        guard let expectedIndex = expected else {
            // Not armed: only the start line arms the timer.
            if inside == 0 {
                expected = 1 % checkpoints.count
                lapStart = now
                return .armed
            }
            return nil
        }

        guard inside == expectedIndex else { return nil }
        if inside == 0 {
            // Full circuit: completing crossing also starts the next lap.
            let duration = now - (lapStart ?? now)
            lapStart = now
            expected = 1 % checkpoints.count
            return .lapCompleted(seconds: duration)
        }
        expected = (expectedIndex + 1) % checkpoints.count
        return nil
    }
}
