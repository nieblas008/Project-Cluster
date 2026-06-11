import Testing

@testable import ClusterProtocol

@Suite struct KartTuningTests {
    /// Pins the shipped handling values. If a tuning change is intentional,
    /// update this test in the same PR — that's the paper trail.
    @Test func standardTuningIsPinned() {
        let t = KartTuning.standard
        #expect(t.acceleration == 14)
        #expect(t.maxSpeed == 12)
        #expect(t.braking == 24)
        #expect(t.coastDrag == 6)
        #expect(t.turnRate == 2.6)
        #expect(t.driftGrip == 0.35)
    }

    @Test func kartsOutrunWalking() {
        // Walking speed will be ~4 tiles/s; karts must be meaningfully faster
        // or what's the point.
        #expect(KartTuning.standard.maxSpeed >= 8)
    }
}
