/// Every kart-handling parameter in one place. "The kart feels wrong" is a PR
/// against these constants, and `KartTuningTests` pins them so accidental
/// changes fail loudly instead of silently changing the game.
public struct KartTuning: Equatable, Sendable {
    /// Tiles/s² while accelerating.
    public var acceleration: Double
    /// Top speed in tiles/s (walking speed is ~4 for comparison).
    public var maxSpeed: Double
    /// Tiles/s² while braking.
    public var braking: Double
    /// Tiles/s² of passive slowdown when coasting.
    public var coastDrag: Double
    /// Steering rate in radians/s at full speed.
    public var turnRate: Double
    /// Lateral grip multiplier while drifting (lower = longer slides).
    public var driftGrip: Double

    public init(
        acceleration: Double,
        maxSpeed: Double,
        braking: Double,
        coastDrag: Double,
        turnRate: Double,
        driftGrip: Double
    ) {
        self.acceleration = acceleration
        self.maxSpeed = maxSpeed
        self.braking = braking
        self.coastDrag = coastDrag
        self.turnRate = turnRate
        self.driftGrip = driftGrip
    }

    public static let standard = KartTuning(
        acceleration: 14,
        maxSpeed: 12,
        braking: 24,
        coastDrag: 6,
        turnRate: 2.6,
        driftGrip: 0.35
    )
}
