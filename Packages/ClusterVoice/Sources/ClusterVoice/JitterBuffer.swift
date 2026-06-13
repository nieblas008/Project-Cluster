import Foundation

/// Per-speaker reorder/conceal buffer. The playback pipeline pops one slot per
/// 20 ms tick; the network pushes whenever packets land. Mic gating means
/// silence never arrives — a long gap is a pause, not loss (ADR 0003).
///
/// The target depth is **adaptive** (Phase 3 part 2): it only ever changes at
/// talk-burst boundaries, never mid-burst, so within a burst playout is as
/// deterministic as a fixed buffer. A burst that needed concealment nudges the
/// depth up (more latency, fewer dropouts); a run of clean bursts eases it back
/// down (less latency).
public struct JitterBuffer: Sendable {
    public enum Slot: Equatable, Sendable {
        /// Play this frame.
        case frame(Data)
        /// Frame lost in transit — conceal (replay last at reduced gain).
        case conceal
        /// Nothing to play (buffering up, or the speaker is just quiet).
        case waiting
    }

    /// Frames buffered before playout starts (4 × 20 ms = 80 ms).
    public static let defaultTargetDepth = 4
    public static let minDepth = 2
    public static let maxDepth = 12
    /// A sequence jump bigger than this is a new talk burst, not loss.
    static let gapResetThreshold: UInt32 = 10
    /// Hard cap on stored frames; beyond it we fast-forward.
    static let capacity = 30
    /// Clean bursts in a row before we try a shallower buffer.
    static let cleanBurstsToShrink = 4

    private var frames: [UInt32: Data] = [:]
    private var nextSeq: UInt32?
    private var playing = false
    private var targetDepth: Int
    private let floorDepth: Int

    // Adaptation + stats counters (cumulative).
    private var concealsThisBurst = 0
    private var cleanBurstStreak = 0
    public private(set) var stats = VoiceStats()

    public init(targetDepth: Int = JitterBuffer.defaultTargetDepth) {
        self.targetDepth = targetDepth
        self.floorDepth = targetDepth  // never adapt below the caller's ask
    }

    public var currentDepth: Int { targetDepth }

    public mutating func push(seq: UInt32, frame: Data) {
        if let next = nextSeq, seq < next {
            stats.lateDropped &+= 1
            return  // too late, playout already passed it
        }
        stats.received &+= 1
        frames[seq] = frame
        if frames.count > Self.capacity, let newest = frames.keys.max() {
            // Way behind (app hang, burst). Fast-forward near the live edge.
            let restart = newest &- UInt32(targetDepth) &+ 1
            frames = frames.filter { $0.key >= restart }
            nextSeq = frames.keys.min()
        }
    }

    public mutating func pop() -> Slot {
        if !playing {
            guard frames.count >= targetDepth, let earliest = frames.keys.min() else {
                return .waiting
            }
            playing = true
            concealsThisBurst = 0
            nextSeq = earliest
        }
        guard let seq = nextSeq else { return .waiting }

        if let frame = frames.removeValue(forKey: seq) {
            nextSeq = seq &+ 1
            stats.played &+= 1
            return .frame(frame)
        }

        guard let earliestAvailable = frames.keys.min() else {
            endBurst()  // buffer dry: speaker stopped. Re-buffer next burst.
            return .waiting
        }
        if earliestAvailable &- seq >= Self.gapResetThreshold {
            // New talk burst after gated silence — jump, don't conceal a pause.
            endBurst()
            nextSeq = earliestAvailable
            playing = frames.count >= targetDepth
            if playing { concealsThisBurst = 0 }
            return playing ? pop() : .waiting
        }
        // Genuine packet loss inside a burst.
        nextSeq = seq &+ 1
        concealsThisBurst &+= 1
        stats.concealed &+= 1
        return .conceal
    }

    /// Adapt depth at the boundary between talk bursts only.
    private mutating func endBurst() {
        playing = false
        if concealsThisBurst > 0 {
            targetDepth = min(targetDepth + 1, Self.maxDepth)
            cleanBurstStreak = 0
        } else {
            cleanBurstStreak &+= 1
            if cleanBurstStreak >= Self.cleanBurstsToShrink {
                targetDepth = max(targetDepth - 1, floorDepth)
                cleanBurstStreak = 0
            }
        }
        concealsThisBurst = 0
    }

    public var bufferedFrameCount: Int { frames.count }
}

/// Receive-side voice health for one speaker (or summed across speakers).
public struct VoiceStats: Equatable, Sendable {
    public var received = 0
    public var played = 0
    public var concealed = 0
    public var lateDropped = 0

    public init() {}

    /// Concealments as a fraction of everything we tried to play. 0 = perfect.
    public var concealmentRate: Double {
        let total = played + concealed
        return total > 0 ? Double(concealed) / Double(total) : 0
    }

    public static func + (lhs: VoiceStats, rhs: VoiceStats) -> VoiceStats {
        var sum = VoiceStats()
        sum.received = lhs.received + rhs.received
        sum.played = lhs.played + rhs.played
        sum.concealed = lhs.concealed + rhs.concealed
        sum.lateDropped = lhs.lateDropped + rhs.lateDropped
        return sum
    }
}
