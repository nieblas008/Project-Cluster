/// Walking, in tile units. The same pure functions run as client prediction
/// and as host validation — divergence is a bug class we delete by sharing.
public struct MoveInput: Equatable, Sendable {
    /// -1, 0, 1 per axis (keyboard intent).
    public var dirX: Int8
    public var dirY: Int8

    public init(dirX: Int8, dirY: Int8) {
        self.dirX = dirX
        self.dirY = dirY
    }

    public static let idle = MoveInput(dirX: 0, dirY: 0)
    public var isMoving: Bool { dirX != 0 || dirY != 0 }
}

public enum Facing: UInt8, Equatable, Sendable {
    case down = 0
    case up = 1
    case left = 2
    case right = 3

    /// Facing follows the dominant input axis; unchanged when idle.
    public static func from(input: MoveInput, previous: Facing) -> Facing {
        guard input.isMoving else { return previous }
        if abs(Int(input.dirX)) >= abs(Int(input.dirY)) && input.dirX != 0 {
            return input.dirX > 0 ? .right : .left
        }
        return input.dirY > 0 ? .down : .up
    }
}

public enum MovementRules {
    /// Tiles per second. Karts (Phase 6) override this in their own config.
    public static let walkSpeed: Double = 4.5
    /// Player collision box half-extent — smaller than half a tile so doorways
    /// one tile wide are comfortable, not pixel-perfect.
    public static let playerHalfExtent: Double = 0.3
    /// Validation slack: accepts jitter/timing wobble, rejects teleports.
    public static let validationSpeedSlack: Double = 1.6
}

public enum MovementSim {
    /// Advance one step with axis-separated AABB collision against the grid.
    public static func step(
        position: Vec2, input: MoveInput, dt: Double, collision: CollisionMap
    ) -> Vec2 {
        guard input.isMoving, dt > 0 else { return position }
        var dx = Double(input.dirX)
        var dy = Double(input.dirY)
        if dx != 0 && dy != 0 {
            let inverseSqrt2 = 0.7071067811865476
            dx *= inverseSqrt2
            dy *= inverseSqrt2
        }
        let speed = MovementRules.walkSpeed
        var result = position
        result.x =
            slideAxis(
                from: result, deltaX: dx * speed * dt, deltaY: 0, collision: collision
            ).x
        result.y =
            slideAxis(
                from: result, deltaX: 0, deltaY: dy * speed * dt, collision: collision
            ).y
        return result
    }

    private static func slideAxis(
        from position: Vec2, deltaX: Double, deltaY: Double, collision: CollisionMap
    ) -> Vec2 {
        let he = MovementRules.playerHalfExtent
        let epsilon = 0.001
        var candidate = Vec2(x: position.x + deltaX, y: position.y + deltaY)

        if !boxCollides(center: candidate, halfExtent: he, collision: collision) {
            return candidate
        }
        // Snap flush against the blocking tile boundary on the moved axis.
        if deltaX > 0 {
            candidate.x = (candidate.x + he).rounded(.down) - he - epsilon
        } else if deltaX < 0 {
            candidate.x = (candidate.x - he).rounded(.up) + he + epsilon
        }
        if deltaY > 0 {
            candidate.y = (candidate.y + he).rounded(.down) - he - epsilon
        } else if deltaY < 0 {
            candidate.y = (candidate.y - he).rounded(.up) + he + epsilon
        }
        // If still colliding (e.g. started overlapped), refuse the move.
        if boxCollides(center: candidate, halfExtent: he, collision: collision) {
            return position
        }
        return candidate
    }

    public static func boxCollides(
        center: Vec2, halfExtent: Double, collision: CollisionMap
    ) -> Bool {
        let minX = Int((center.x - halfExtent).rounded(.down))
        let maxX = Int((center.x + halfExtent).rounded(.down))
        let minY = Int((center.y - halfExtent).rounded(.down))
        let maxY = Int((center.y + halfExtent).rounded(.down))
        for tileY in minY...maxY {
            for tileX in minX...maxX {
                if collision.isSolid(tileX: tileX, tileY: tileY) {
                    return true
                }
            }
        }
        return false
    }

    /// Host-side gate for client-authoritative positions (PLAN §7): clamp
    /// impossible speed, refuse wall clips and out-of-bounds.
    public static func validate(
        previous: Vec2, proposed: Vec2, dt: Double, collision: CollisionMap
    ) -> Vec2 {
        let maxDistance = MovementRules.walkSpeed * max(dt, 0.001) * MovementRules.validationSpeedSlack
        var accepted = proposed
        let travel = previous.distance(to: proposed)
        if travel > maxDistance {
            let t = maxDistance / travel
            accepted = lerp(previous, proposed, t: t)
        }
        if boxCollides(
            center: accepted, halfExtent: MovementRules.playerHalfExtent, collision: collision)
        {
            return previous
        }
        return accepted
    }
}
