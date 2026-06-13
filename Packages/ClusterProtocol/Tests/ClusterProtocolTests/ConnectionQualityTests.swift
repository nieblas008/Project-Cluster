import Testing

@testable import ClusterProtocol

@Suite struct ConnectionQualityTests {
    @Test func noSnapshotsIsLost() {
        let estimator = ConnectionQualityEstimator()
        #expect(estimator.quality(now: 100) == .lost)
    }

    @Test func steadyTickReadsGood() {
        var estimator = ConnectionQualityEstimator()
        var t = 0.0
        for _ in 0..<20 {
            estimator.recordArrival(at: t)
            t += 0.066  // ~15 Hz
        }
        #expect(estimator.quality(now: t) == .good)
    }

    @Test func occasionalLargeGapReadsFair() {
        var estimator = ConnectionQualityEstimator()
        estimator.recordArrival(at: 0.0)
        estimator.recordArrival(at: 0.066)
        estimator.recordArrival(at: 0.5)  // ~430 ms gap
        estimator.recordArrival(at: 0.566)
        #expect(estimator.quality(now: 0.6) == .fair)
    }

    @Test func longSilenceSinceLastReadsLost() {
        var estimator = ConnectionQualityEstimator()
        estimator.recordArrival(at: 0.0)
        estimator.recordArrival(at: 0.066)
        // Nothing for 3 s.
        #expect(estimator.quality(now: 3.0) == .lost)
        #expect(estimator.quality(now: 0.8) == .poor)  // >600ms but <2s
    }

    @Test func qualityOrders() {
        #expect(ConnectionQuality.lost < .poor)
        #expect(ConnectionQuality.poor < .fair)
        #expect(ConnectionQuality.fair < .good)
    }
}
