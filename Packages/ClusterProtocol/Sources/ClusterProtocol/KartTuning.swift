/// Every kart-handling parameter in one place. "The kart feels wrong" is a PR
/// against these constants, and `KartTuningTests` pins them so accidental
/// changes fail loudly instead of silently changing the game.
public struct KartTuning: Equatable, Sendable {
    /// Tiles/s² while accelerating.
    public var acceleration: Double
    /// Top speed in tiles/s (walking speed is ~4.5 for comparison).
    public var maxSpeed: Double
    /// Top reverse speed in tiles/s.
    public var maxReverseSpeed: Double
    /// Tiles/s² while braking.
    public var braking: Double
    /// Tiles/s² of passive slowdown when coasting.
    public var coastDrag: Double
    /// Steering rate in radians/s at full speed.
    public var turnRate: Double
    /// Turn-rate multiplier while the handbrake is held (ADR 0006 drift).
    public var driftTurnBoost: Double
    /// Fraction of speed kept after hitting a wall — a thunk, not a stop.
    public var wallSpeedRetention: Double
    /// Collision half-extent in tiles (a kart is wider than a walker).
    public var halfExtent: Double

    public init(
        acceleration: Double,
        maxSpeed: Double,
        maxReverseSpeed: Double,
        braking: Double,
        coastDrag: Double,
        turnRate: Double,
        driftTurnBoost: Double,
        wallSpeedRetention: Double,
        halfExtent: Double
    ) {
        self.acceleration = acceleration
        self.maxSpeed = maxSpeed
        self.maxReverseSpeed = maxReverseSpeed
        self.braking = braking
        self.coastDrag = coastDrag
        self.turnRate = turnRate
        self.driftTurnBoost = driftTurnBoost
        self.wallSpeedRetention = wallSpeedRetention
        self.halfExtent = halfExtent
    }

    public static let standard = KartTuning(
        acceleration: 14,
        maxSpeed: 12,
        maxReverseSpeed: 3,
        braking: 24,
        coastDrag: 6,
        turnRate: 2.6,
        driftTurnBoost: 1.6,
        wallSpeedRetention: 0.3,
        halfExtent: 0.35
    )
}
