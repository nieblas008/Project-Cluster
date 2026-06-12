import Foundation

/// Per-speaker reorder/conceal buffer. The playback pipeline pops one slot per
/// 20 ms tick; the network pushes whenever packets land. Mic gating means
/// silence never arrives — a long gap is a pause, not loss (ADR 0003).
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
    /// A sequence jump bigger than this is a new talk burst, not loss.
    static let gapResetThreshold: UInt32 = 10
    /// Hard cap on stored frames; beyond it we fast-forward.
    static let capacity = 25

    private var frames: [UInt32: Data] = [:]
    private var nextSeq: UInt32?
    private var playing = false
    private let targetDepth: Int

    public init(targetDepth: Int = JitterBuffer.defaultTargetDepth) {
        self.targetDepth = targetDepth
    }

    public mutating func push(seq: UInt32, frame: Data) {
        if let next = nextSeq, seq < next {
            return  // too late, playout already passed it
        }
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
            nextSeq = earliest
        }
        guard let seq = nextSeq else { return .waiting }

        if let frame = frames.removeValue(forKey: seq) {
            nextSeq = seq &+ 1
            return .frame(frame)
        }

        guard let earliestAvailable = frames.keys.min() else {
            // Buffer dry: the speaker stopped talking. Re-buffer next burst.
            playing = false
            return .waiting
        }
        if earliestAvailable &- seq >= Self.gapResetThreshold {
            // New talk burst after gated silence — jump, don't conceal a pause.
            nextSeq = earliestAvailable
            playing = frames.count >= targetDepth
            return playing ? pop() : .waiting
        }
        // Genuine packet loss inside a burst.
        nextSeq = seq &+ 1
        return .conceal
    }

    public var bufferedFrameCount: Int { frames.count }
}
