import Testing

@testable import ClusterProtocol

@Suite struct ProximityTests {
    let rules = ProximityRules.standard

    @Test func fullVolumeInsideInnerRadius() {
        #expect(rules.gain(atDistance: 0) == 1)
        #expect(rules.gain(atDistance: 5) == 1)
    }

    @Test func fadesLinearlyAcrossTheBand() {
        #expect(rules.gain(atDistance: 7.5) == 0.5)
        #expect(abs(rules.gain(atDistance: 6) - 0.8) < 1e-9)
    }

    @Test func silentAndUnsubscribedBeyondOuterRadius() {
        #expect(rules.gain(atDistance: 10) == 0)
        #expect(rules.gain(atDistance: 40) == 0)
        #expect(!rules.isAudible(atDistance: 10))
        #expect(rules.isAudible(atDistance: 9.99))
    }

    @Test func standardRadiiMatchThePlan() {
        // docs/PLAN.md §8: ≤5 tiles full, 5→10 fade, >10 unsubscribed.
        #expect(rules.fullVolumeRadius == 5)
        #expect(rules.silenceRadius == 10)
    }
}
