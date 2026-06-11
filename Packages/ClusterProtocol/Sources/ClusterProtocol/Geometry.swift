/// 2D vector in tile units. The simulation never thinks in pixels;
/// rendering scales tiles to points at the SpriteKit layer.
public struct Vec2: Equatable, Hashable, Sendable, Codable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero = Vec2(x: 0, y: 0)

    public static func + (lhs: Vec2, rhs: Vec2) -> Vec2 {
        Vec2(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
    }

    public static func - (lhs: Vec2, rhs: Vec2) -> Vec2 {
        Vec2(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
    }

    public static func * (lhs: Vec2, rhs: Double) -> Vec2 {
        Vec2(x: lhs.x * rhs, y: lhs.y * rhs)
    }

    public var length: Double {
        (x * x + y * y).squareRoot()
    }

    public func distance(to other: Vec2) -> Double {
        (other - self).length
    }
}

public func clamp<T: Comparable>(_ value: T, _ lower: T, _ upper: T) -> T {
    min(max(value, lower), upper)
}

/// Linear interpolation with `t` clamped to [0, 1] — remote avatars are rendered
/// by lerping between buffered snapshots, so out-of-range `t` must never extrapolate
/// wildly on a late packet.
public func lerp(_ a: Double, _ b: Double, t: Double) -> Double {
    let t = clamp(t, 0, 1)
    return a + (b - a) * t
}

public func lerp(_ a: Vec2, _ b: Vec2, t: Double) -> Vec2 {
    Vec2(x: lerp(a.x, b.x, t: t), y: lerp(a.y, b.y, t: t))
}
