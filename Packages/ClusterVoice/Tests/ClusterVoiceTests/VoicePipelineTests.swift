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
        #expect(jitter.bufferedFrameCount <= 25)
        // First pop should be near the live edge, not seq 1.
        if case .frame(let frame) = jitter.pop() {
            #expect(frame != data(1))
        } else {
            Issue.record("expected a frame")
        }
    }
}
