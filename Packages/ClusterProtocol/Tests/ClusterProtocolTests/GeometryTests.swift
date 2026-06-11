import Testing

@testable import ClusterProtocol

@Suite struct GeometryTests {
    @Test func vectorArithmetic() {
        let a = Vec2(x: 1, y: 2)
        let b = Vec2(x: 4, y: 6)
        #expect(a + b == Vec2(x: 5, y: 8))
        #expect(b - a == Vec2(x: 3, y: 4))
        #expect((b - a).length == 5)
        #expect(a.distance(to: b) == 5)
        #expect(a * 2 == Vec2(x: 2, y: 4))
    }

    @Test func lerpInterpolatesAndClamps() {
        #expect(lerp(0, 10, t: 0.5) == 5)
        #expect(lerp(0, 10, t: 0) == 0)
        #expect(lerp(0, 10, t: 1) == 10)
        // A late snapshot must never extrapolate.
        #expect(lerp(0, 10, t: 1.7) == 10)
        #expect(lerp(0, 10, t: -0.3) == 0)
        #expect(lerp(Vec2.zero, Vec2(x: 4, y: -2), t: 0.25) == Vec2(x: 1, y: -0.5))
    }
}
