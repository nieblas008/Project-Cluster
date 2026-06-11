import Testing

@testable import ClusterVoice

@Suite struct VoiceFormatTests {
    @Test func frameMathIsConsistent() {
        #expect(
            Double(VoiceFormat.samplesPerFrame)
                == VoiceFormat.sampleRate * VoiceFormat.frameDuration)
    }

    @Test func formatMatchesThePlan() {
        // docs/PLAN.md §8: 48 kHz mono, 20 ms frames, ~32–48 kbps.
        #expect(VoiceFormat.sampleRate == 48_000)
        #expect(VoiceFormat.channels == 1)
        #expect(VoiceFormat.frameDuration == 0.020)
        #expect((32_000...48_000).contains(VoiceFormat.targetBitrate))
    }
}
