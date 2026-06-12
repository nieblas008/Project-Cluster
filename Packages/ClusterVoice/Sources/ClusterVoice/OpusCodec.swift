@preconcurrency import AVFoundation

/// Opus via Apple's native codec — no vendored libopus (ADR 0003).
/// Encoder and decoder are stateful: one encoder per mic, one decoder per
/// remote speaker.
public enum OpusCodecError: Error {
    case formatUnavailable
    case converterUnavailable
    case conversionFailed(String)
}

enum OpusFormats {
    static func pcm() -> AVAudioFormat {
        AVAudioFormat(
            standardFormatWithSampleRate: VoiceFormat.sampleRate,
            channels: AVAudioChannelCount(VoiceFormat.channels))!
    }

    static func opus() throws -> AVAudioFormat {
        var description = AudioStreamBasicDescription(
            mSampleRate: VoiceFormat.sampleRate,
            mFormatID: kAudioFormatOpus,
            mFormatFlags: 0,
            mBytesPerPacket: 0,
            mFramesPerPacket: UInt32(VoiceFormat.samplesPerFrame),
            mBytesPerFrame: 0,
            mChannelsPerFrame: UInt32(VoiceFormat.channels),
            mBitsPerChannel: 0,
            mReserved: 0
        )
        guard let format = AVAudioFormat(streamDescription: &description) else {
            throw OpusCodecError.formatUnavailable
        }
        return format
    }
}

public final class OpusEncoder {
    private let converter: AVAudioConverter
    private let opusFormat: AVAudioFormat

    public init() throws {
        let opusFormat = try OpusFormats.opus()
        guard let converter = AVAudioConverter(from: OpusFormats.pcm(), to: opusFormat) else {
            throw OpusCodecError.converterUnavailable
        }
        converter.bitRate = VoiceFormat.targetBitrate
        self.converter = converter
        self.opusFormat = opusFormat
    }

    /// One 960-sample PCM buffer in → one Opus packet out.
    public func encode(_ buffer: AVAudioPCMBuffer) throws -> Data {
        let packet = AVAudioCompressedBuffer(
            format: opusFormat, packetCapacity: 1, maximumPacketSize: 1500)
        var consumed = false
        var conversionError: NSError?
        let status = converter.convert(to: packet, error: &conversionError) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, packet.byteLength > 0 else {
            throw OpusCodecError.conversionFailed(
                conversionError?.localizedDescription ?? "encode status \(status.rawValue)")
        }
        return Data(bytes: packet.data, count: Int(packet.byteLength))
    }
}

public final class OpusDecoder {
    private let converter: AVAudioConverter
    private let opusFormat: AVAudioFormat
    private let pcmFormat = OpusFormats.pcm()

    public init() throws {
        let opusFormat = try OpusFormats.opus()
        guard let converter = AVAudioConverter(from: opusFormat, to: pcmFormat) else {
            throw OpusCodecError.converterUnavailable
        }
        self.converter = converter
        self.opusFormat = opusFormat
    }

    /// One Opus packet in → one PCM buffer out (≤ 960 frames; the first call
    /// after init returns slightly fewer due to decoder priming).
    public func decode(_ data: Data) throws -> AVAudioPCMBuffer {
        let packet = AVAudioCompressedBuffer(
            format: opusFormat, packetCapacity: 1, maximumPacketSize: max(data.count, 1))
        data.withUnsafeBytes { raw in
            packet.data.copyMemory(from: raw.baseAddress!, byteCount: raw.count)
        }
        packet.byteLength = UInt32(data.count)
        packet.packetCount = 1
        if let descriptions = packet.packetDescriptions {
            descriptions.pointee = AudioStreamPacketDescription(
                mStartOffset: 0, mVariableFramesInPacket: 0, mDataByteSize: UInt32(data.count))
        }

        guard
            let output = AVAudioPCMBuffer(
                pcmFormat: pcmFormat,
                frameCapacity: AVAudioFrameCount(VoiceFormat.samplesPerFrame * 2))
        else { throw OpusCodecError.conversionFailed("buffer allocation") }

        var consumed = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return packet
        }
        guard status != .error else {
            throw OpusCodecError.conversionFailed(
                conversionError?.localizedDescription ?? "decode status \(status.rawValue)")
        }
        return output
    }
}

extension AVAudioPCMBuffer {
    /// Root-mean-square level — the sender's mic gate and the UI level dot.
    public var rmsLevel: Float {
        guard let samples = floatChannelData?[0], frameLength > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<Int(frameLength) {
            sum += samples[i] * samples[i]
        }
        return (sum / Float(frameLength)).squareRoot()
    }
}
