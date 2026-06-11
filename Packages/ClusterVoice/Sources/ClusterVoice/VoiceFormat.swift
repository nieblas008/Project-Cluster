/// The audio contract between capture, codec, transport, and playback.
/// Every Phase 3 component is built against these numbers; changing one is a
/// wire-version event, not a tweak.
public enum VoiceFormat {
    /// Capture/playback sample rate. Opus native, AVAudioEngine friendly.
    public static let sampleRate: Double = 48_000
    public static let channels = 1
    /// One encoded packet per 20 ms frame — Opus's sweet spot for VoIP.
    public static let frameDuration: Double = 0.020
    public static let samplesPerFrame = 960  // 48_000 × 0.020
    /// Target encoder bitrate; voice-only lives comfortably here.
    public static let targetBitrate = 40_000
    /// Initial jitter-buffer depth; adapts at runtime within bounds (Phase 3).
    public static let initialJitterBufferSeconds: Double = 0.08
}
