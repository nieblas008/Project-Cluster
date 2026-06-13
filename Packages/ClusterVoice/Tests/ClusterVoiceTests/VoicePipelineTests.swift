import AVFoundation
import Testing

@testable import ClusterVoice

@Suite struct OpusCodecTests {
    func sineBuffer(frequency: Float = 440, amplitude: Float = 0.5) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(
            standardFormatWithSampleRate: VoiceFormat.sampleRate, channels: 1)!
        let buffer = AVAudioPCMBuffer(
            pcmFormat: format, frameCapacity: AVAudioFrameCount(VoiceFormat.samplesPerFrame))!
        buffer.frameLength = AVAudioFrameCount(VoiceFormat.samplesPerFrame)
        for i in 0..<VoiceFormat.samplesPerFrame {
            buffer.floatChannelData![0][i] =
                sin(Float(i) * 2 * .pi * frequency / Float(VoiceFormat.sampleRate)) * amplitude
        }
        return buffer
    }

    @Test func encodeProducesCompactPackets() throws {
        let encoder = try OpusEncoder()
        let packet = try encoder.encode(sineBuffer())
        // 20 ms at ~40 kbps ≈ 100 bytes; anything under MTU and over zero is sane.
        #expect(packet.count > 10 && packet.count < 400)
    }

    @Test func roundTripPreservesSignalEnergy() throws {
        let encoder = try OpusEncoder()
        let decoder = try OpusDecoder()

        // Streamed: later frames decode at full length once primed.
        var totalEnergy: Float = 0
        var decodedFrames = 0
        for _ in 0..<5 {
            let packet = try encoder.encode(sineBuffer())
            let pcm = try decoder.decode(packet)
            totalEnergy += pcm.rmsLevel
            decodedFrames += Int(pcm.frameLength)
        }
        #expect(totalEnergy > 0.5)  // a 0.5-amplitude sine has RMS ≈ 0.35/frame
        #expect(decodedFrames > VoiceFormat.samplesPerFrame * 3)
    }

    @Test func silenceHasNearZeroRMS() throws {
        let format = AVAudioFormat(
            standardFormatWithSampleRate: VoiceFormat.sampleRate, channels: 1)!
        let silent = AVAudioPCMBuffer(
            pcmFormat: format, frameCapacity: AVAudioFrameCount(VoiceFormat.samplesPerFrame))!
        silent.frameLength = AVAudioFrameCount(VoiceFormat.samplesPerFrame)
        #expect(silent.rmsLevel < 0.001)
        #expect(sineBuffer().rmsLevel > 0.2)
    }
}

@Suite struct JitterBufferTests {
    func data(_ seq: UInt32) -> Data {
        Data([UInt8(seq % 250)])
    }

    @Test func buffersToDepthThenPlaysInOrder() {
        var jitter = JitterBuffer(targetDepth: 3)
        #expect(jitter.pop() == .waiting)
        jitter.push(seq: 1, frame: data(1))
        jitter.push(seq: 2, frame: data(2))
        #expect(jitter.pop() == .waiting)  // not at depth yet
        jitter.push(seq: 3, frame: data(3))
        #expect(jitter.pop() == .frame(data(1)))
        #expect(jitter.pop() == .frame(data(2)))
        #expect(jitter.pop() == .frame(data(3)))
    }

    @Test func reorderedPacketsComeOutInOrder() {
        var jitter = JitterBuffer(targetDepth: 3)
        jitter.push(seq: 2, frame: data(2))
        jitter.push(seq: 3, frame: data(3))
        jitter.push(seq: 1, frame: data(1))
        #expect(jitter.pop() == .frame(data(1)))
        #expect(jitter.pop() == .frame(data(2)))
        #expect(jitter.pop() == .frame(data(3)))
    }

    @Test func lossInsideABurstConceals() {
        var jitter = JitterBuffer(targetDepth: 2)
        jitter.push(seq: 1, frame: data(1))
        jitter.push(seq: 2, frame: data(2))
        jitter.push(seq: 4, frame: data(4))  // 3 lost
        #expect(jitter.pop() == .frame(data(1)))
        #expect(jitter.pop() == .frame(data(2)))
        #expect(jitter.pop() == .conceal)
        #expect(jitter.pop() == .frame(data(4)))
    }

    @Test func gatedPauseDoesNotConcealForever() {
        var jitter = JitterBuffer(targetDepth: 2)
        jitter.push(seq: 1, frame: data(1))
        jitter.push(seq: 2, frame: data(2))
        #expect(jitter.pop() == .frame(data(1)))
        #expect(jitter.pop() == .frame(data(2)))
        #expect(jitter.pop() == .waiting)  // speaker went quiet — no concealment

        // New burst much later (mic gate gap) starts cleanly after re-buffering.
        jitter.push(seq: 100, frame: data(100))
        #expect(jitter.pop() == .waiting)
        jitter.push(seq: 101, frame: data(101))
        #expect(jitter.pop() == .frame(data(100)))
        #expect(jitter.pop() == .frame(data(101)))
    }

    @Test func latePacketsAreDropped() {
        var jitter = JitterBuffer(targetDepth: 2)
        jitter.push(seq: 5, frame: data(5))
        jitter.push(seq: 6, frame: data(6))
        #expect(jitter.pop() == .frame(data(5)))
        jitter.push(seq: 4, frame: data(4))  // already played past it
        #expect(jitter.pop() == .frame(data(6)))
        #expect(jitter.bufferedFrameCount == 0)
    }

    @Test func overflowFastForwardsToLiveEdge() {
        var jitter = JitterBuffer(targetDepth: 2)
        for seq in 1...40 {
            jitter.push(seq: UInt32(seq), frame: data(UInt32(seq)))
        }
        #expect(jitter.bufferedFrameCount <= 30)
        // First pop should be near the live edge, not seq 1.
        if case .frame(let frame) = jitter.pop() {
            #expect(frame != data(1))
        } else {
            Issue.record("expected a frame")
        }
    }

    @Test func statsCountPlayConcealAndLateDrops() {
        var jitter = JitterBuffer(targetDepth: 2)
        jitter.push(seq: 1, frame: data(1))
        jitter.push(seq: 2, frame: data(2))
        jitter.push(seq: 4, frame: data(4))  // 3 lost
        _ = jitter.pop()  // 1
        _ = jitter.pop()  // 2
        _ = jitter.pop()  // conceal (3)
        _ = jitter.pop()  // 4
        jitter.push(seq: 2, frame: data(2))  // late
        #expect(jitter.stats.played == 3)
        #expect(jitter.stats.concealed == 1)
        #expect(jitter.stats.lateDropped == 1)
        #expect(jitter.stats.concealmentRate > 0 && jitter.stats.concealmentRate < 0.5)
    }

    @Test func depthGrowsAfterAConcealedBurst() {
        var jitter = JitterBuffer(targetDepth: 2)
        #expect(jitter.currentDepth == 2)
        // Burst with a hole, then dry → endBurst sees a conceal.
        jitter.push(seq: 1, frame: data(1))
        jitter.push(seq: 2, frame: data(2))
        jitter.push(seq: 4, frame: data(4))
        _ = jitter.pop()  // 1
        _ = jitter.pop()  // 2
        _ = jitter.pop()  // conceal 3
        _ = jitter.pop()  // 4
        _ = jitter.pop()  // dry → endBurst (had a conceal) → depth up
        #expect(jitter.currentDepth == 3)
    }

    @Test func depthNeverDropsBelowTheCallersFloor() {
        var jitter = JitterBuffer(targetDepth: 4)
        // Several clean bursts; depth must not sink under the requested 4.
        for burst in 0..<8 {
            let base = UInt32(burst * 100 + 1)
            jitter.push(seq: base, frame: data(base))
            jitter.push(seq: base + 1, frame: data(base + 1))
            jitter.push(seq: base + 2, frame: data(base + 2))
            jitter.push(seq: base + 3, frame: data(base + 3))
            while case .frame = jitter.pop() {}
            _ = jitter.pop()
        }
        #expect(jitter.currentDepth >= 4)
    }
}
