/// The proximity-audio curve: full volume up close, linear fade, then silence.
/// The host also uses `isAudible` to decide whether to forward a speaker's
/// packets to a receiver at all (beyond the fade radius nothing is sent).
public struct ProximityRules: Equatable, Sendable {
    /// Inside this distance (in tiles) a speaker is heard at full volume.
    public var fullVolumeRadius: Double
    /// Beyond this distance a speaker is silent and unsubscribed.
    public var silenceRadius: Double

    public init(fullVolumeRadius: Double, silenceRadius: Double) {
        precondition(silenceRadius > fullVolumeRadius, "fade band must have positive width")
        self.fullVolumeRadius = fullVolumeRadius
        self.silenceRadius = silenceRadius
    }

    public static let standard = ProximityRules(fullVolumeRadius: 5, silenceRadius: 10)

    /// Gain in [0, 1] for a speaker at `distance` tiles.
    public func gain(atDistance distance: Double) -> Double {
        if distance <= fullVolumeRadius { return 1 }
        if distance >= silenceRadius { return 0 }
        return 1 - (distance - fullVolumeRadius) / (silenceRadius - fullVolumeRadius)
    }

    public func isAudible(atDistance distance: Double) -> Bool {
        distance < silenceRadius
    }
}
