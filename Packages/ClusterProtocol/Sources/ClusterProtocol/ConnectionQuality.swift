/// A traffic-light health read derived from how regularly the host's 15 Hz
/// snapshots arrive at a client. Snapshots are the metronome that never stops
/// while the link is healthy, so the gap between them is a good, payload-free
/// proxy for "how's my connection right now".
public enum ConnectionQuality: Int, Comparable, Sendable {
    case good = 3
    case fair = 2
    case poor = 1
    /// No recent snapshots at all.
    case lost = 0

    public static func < (lhs: ConnectionQuality, rhs: ConnectionQuality) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var label: String {
        switch self {
        case .good: "Good"
        case .fair: "Fair"
        case .poor: "Poor"
        case .lost: "Lost"
        }
    }
}

/// Rolling estimator: feed it snapshot arrival timestamps, ask for the verdict.
/// Pure and clock-injectable so it's unit-testable without real time.
public struct ConnectionQualityEstimator: Sendable {
    /// Host tick is ~66 ms; allow comfortable slack before calling it degraded.
    static let goodGap = 0.20
    static let fairGap = 0.60
    static let lostGap = 2.0
    private static let windowSize = 30

    private var arrivals: [Double] = []

    public init() {}

    public mutating func recordArrival(at time: Double) {
        arrivals.append(time)
        if arrivals.count > Self.windowSize {
            arrivals.removeFirst(arrivals.count - Self.windowSize)
        }
    }

    /// Verdict as of `now`. Worst of "time since last snapshot" and "recent
    /// worst gap" — a single late snapshot shouldn't read green, and a long
    /// silence shouldn't read green just because earlier gaps were tight.
    public func quality(now: Double) -> ConnectionQuality {
        guard let last = arrivals.last else { return .lost }
        let sinceLast = now - last
        if sinceLast >= Self.lostGap { return .lost }

        var worstGap = sinceLast
        if arrivals.count >= 2 {
            for i in 1..<arrivals.count {
                worstGap = max(worstGap, arrivals[i] - arrivals[i - 1])
            }
        }
        if worstGap <= Self.goodGap { return .good }
        if worstGap <= Self.fairGap { return .fair }
        return .poor
    }
}
