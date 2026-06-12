@preconcurrency import AVFoundation
import CoreAudio
import Foundation

/// Capture and playback, built on AVAudioEngine with Apple's voice-processed
/// I/O — which is what supplies echo cancellation, noise suppression, and gain
/// control (PLAN §8: "Apple ships the hard DSP").
///
/// Capture path: voice-processed input tap → resample to 48 kHz mono →
/// 960-sample chunks → RMS mic gate (silence is never sent) → Opus →
/// `onEncodedFrame` (called on the engine's processing queue).
///
/// Playback path: `enqueue` feeds a per-speaker pipeline (jitter buffer →
/// Opus decode → AVAudioPlayerNode); one 20 ms timer services them all.
/// Per-speaker volume is the proximity gain.
public final class VoiceEngine: @unchecked Sendable {
    public struct InputDevice: Identifiable, Equatable, Sendable {
        public let id: AudioDeviceID
        public let name: String
    }

    public enum VoiceEngineError: Error {
        case microphonePermissionDenied
        case engineStartFailed(String)
    }

    /// Opus frame + the chunk's RMS level. Processing-queue context.
    public var onEncodedFrame: (@Sendable (Data, Float) -> Void)?
    /// Level updates even while muted (drives the UI meter). Processing queue.
    public var onLevel: (@Sendable (Float) -> Void)?

    private let queue = DispatchQueue(label: "cluster.voice.engine")
    private let engine = AVAudioEngine()
    private let pcmFormat = OpusFormats.pcm()

    private var encoder: OpusEncoder?
    private var captureConverter: AVAudioConverter?
    private var pending: [Float] = []
    private var muted = false
    private var gateOpenFrames = 0
    private var running = false

    private final class SpeakerPipeline {
        let player = AVAudioPlayerNode()
        var jitter = JitterBuffer()
        let decoder: OpusDecoder
        var lastBuffer: AVAudioPCMBuffer?
        init(decoder: OpusDecoder) {
            self.decoder = decoder
        }
    }
    private var pipelines: [UInt64: SpeakerPipeline] = [:]
    private var playoutTimer: DispatchSourceTimer?

    public init() {}

    // MARK: Lifecycle

    public func start() async throws {
        let granted = await withCheckedContinuation { cont in
            AVCaptureDevice.requestAccess(for: .audio) { cont.resume(returning: $0) }
        }
        guard granted else { throw VoiceEngineError.microphonePermissionDenied }

        try queue.sync {
            guard !running else { return }
            do {
                // The whole reason DIY voice is feasible: Apple's AEC/NS/AGC.
                try engine.inputNode.setVoiceProcessingEnabled(true)
            } catch {
                // Degraded but functional (headphone users won't echo anyway).
            }
            encoder = try OpusEncoder()

            let inputFormat = engine.inputNode.outputFormat(forBus: 0)
            captureConverter = AVAudioConverter(from: inputFormat, to: pcmFormat)
            engine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) {
                [weak self] buffer, _ in
                self?.queue.async { self?.ingestCapture(buffer) }
            }

            engine.prepare()
            do {
                try engine.start()
            } catch {
                engine.inputNode.removeTap(onBus: 0)
                throw VoiceEngineError.engineStartFailed(error.localizedDescription)
            }
            running = true
            startPlayoutTimer()
        }
    }

    public func stop() {
        queue.sync {
            guard running else { return }
            running = false
            playoutTimer?.cancel()
            playoutTimer = nil
            engine.inputNode.removeTap(onBus: 0)
            for pipeline in pipelines.values {
                pipeline.player.stop()
                engine.detach(pipeline.player)
            }
            pipelines.removeAll()
            engine.stop()
            pending.removeAll()
        }
    }

    public func setMuted(_ value: Bool) {
        queue.async { self.muted = value }
    }

    // MARK: Capture

    private func ingestCapture(_ buffer: AVAudioPCMBuffer) {
        guard running, let converter = captureConverter else { return }
        let ratio = pcmFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let converted = AVAudioPCMBuffer(pcmFormat: pcmFormat, frameCapacity: capacity)
        else { return }

        var consumed = false
        var conversionError: NSError?
        let status = converter.convert(to: converted, error: &conversionError) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, converted.frameLength > 0,
            let samples = converted.floatChannelData?[0]
        else { return }

        pending.append(contentsOf: UnsafeBufferPointer(start: samples, count: Int(converted.frameLength)))

        while pending.count >= VoiceFormat.samplesPerFrame {
            let chunk = Array(pending.prefix(VoiceFormat.samplesPerFrame))
            pending.removeFirst(VoiceFormat.samplesPerFrame)
            emit(chunk: chunk)
        }
    }

    private func emit(chunk: [Float]) {
        guard
            let frameBuffer = AVAudioPCMBuffer(
                pcmFormat: pcmFormat, frameCapacity: AVAudioFrameCount(VoiceFormat.samplesPerFrame))
        else { return }
        frameBuffer.frameLength = AVAudioFrameCount(VoiceFormat.samplesPerFrame)
        chunk.withUnsafeBufferPointer { source in
            frameBuffer.floatChannelData![0].update(from: source.baseAddress!, count: chunk.count)
        }

        let level = frameBuffer.rmsLevel
        onLevel?(level)

        // Gate: open on signal, stay open through brief dips (hangover) so
        // word endings aren't clipped. Muted = gate welded shut.
        if !muted && level > VoiceFormat.gateThreshold {
            gateOpenFrames = VoiceFormat.gateHangoverFrames
        } else if gateOpenFrames > 0 {
            gateOpenFrames -= 1
        }
        guard !muted, gateOpenFrames > 0, let encoder else { return }

        if let opus = try? encoder.encode(frameBuffer) {
            onEncodedFrame?(opus, level)
        }
    }

    // MARK: Playback

    public func enqueue(speakerID: UInt64, seq: UInt32, opus: Data) {
        queue.async {
            guard self.running else { return }
            let pipeline: SpeakerPipeline
            if let existing = self.pipelines[speakerID] {
                pipeline = existing
            } else {
                guard let decoder = try? OpusDecoder() else { return }
                pipeline = SpeakerPipeline(decoder: decoder)
                self.engine.attach(pipeline.player)
                self.engine.connect(
                    pipeline.player, to: self.engine.mainMixerNode, format: self.pcmFormat)
                pipeline.player.play()
                self.pipelines[speakerID] = pipeline
            }
            pipeline.jitter.push(seq: seq, frame: opus)
        }
    }

    /// Proximity gain, 0…1 (PLAN §8). Beyond the silence radius the host has
    /// already unsubscribed us, so 0 here is belt-and-suspenders.
    public func setVolume(speakerID: UInt64, _ volume: Float) {
        queue.async {
            self.pipelines[speakerID]?.player.volume = max(0, min(volume, 1))
        }
    }

    public func removeSpeaker(_ speakerID: UInt64) {
        queue.async {
            guard let pipeline = self.pipelines.removeValue(forKey: speakerID) else { return }
            pipeline.player.stop()
            self.engine.detach(pipeline.player)
        }
    }

    private func startPlayoutTimer() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(
            deadline: .now() + VoiceFormat.frameDuration,
            repeating: VoiceFormat.frameDuration, leeway: .milliseconds(4))
        timer.setEventHandler { [weak self] in
            self?.servicePipelines()
        }
        timer.resume()
        playoutTimer = timer
    }

    private func servicePipelines() {
        for pipeline in pipelines.values {
            switch pipeline.jitter.pop() {
            case .frame(let opus):
                if let pcm = try? pipeline.decoder.decode(opus), pcm.frameLength > 0 {
                    pipeline.lastBuffer = pcm
                    pipeline.player.scheduleBuffer(pcm, completionHandler: nil)
                }
            case .conceal:
                // No native PLC through CoreAudio (ADR 0003): replay the last
                // frame — at 20 ms, far less audible than a dropout click.
                if let last = pipeline.lastBuffer {
                    pipeline.player.scheduleBuffer(last, completionHandler: nil)
                }
            case .waiting:
                break
            }
        }
    }

    // MARK: Input devices

    public static func availableInputDevices() -> [InputDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard
            AudioObjectGetPropertyDataSize(
                AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr
        else { return [] }
        var deviceIDs = [AudioDeviceID](
            repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceIDs)
                == noErr
        else { return [] }

        return deviceIDs.compactMap { id in
            guard inputChannelCount(of: id) > 0, let name = deviceName(of: id) else { return nil }
            return InputDevice(id: id, name: name)
        }
    }

    /// Best-effort device switch: restarts the capture side.
    public func setInputDevice(_ deviceID: AudioDeviceID) throws {
        try queue.sync {
            let wasRunning = running
            if wasRunning {
                engine.inputNode.removeTap(onBus: 0)
                engine.stop()
            }
            try engine.inputNode.auAudioUnit.setDeviceID(deviceID)
            if wasRunning {
                let inputFormat = engine.inputNode.outputFormat(forBus: 0)
                captureConverter = AVAudioConverter(from: inputFormat, to: pcmFormat)
                engine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) {
                    [weak self] buffer, _ in
                    self?.queue.async { self?.ingestCapture(buffer) }
                }
                engine.prepare()
                try engine.start()
            }
        }
    }

    private static func inputChannelCount(of device: AudioDeviceID) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr, size > 0
        else { return 0 }
        let bufferList = UnsafeMutablePointer<AudioBufferList>.allocate(
            capacity: Int(size) / MemoryLayout<AudioBufferList>.stride + 1)
        defer { bufferList.deallocate() }
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, bufferList) == noErr
        else { return 0 }
        return UnsafeMutableAudioBufferListPointer(bufferList).reduce(0) {
            $0 + Int($1.mNumberChannels)
        }
    }

    private static func deviceName(of device: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var name: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        let status = withUnsafeMutablePointer(to: &name) { pointer in
            AudioObjectGetPropertyData(device, &address, 0, nil, &size, pointer)
        }
        guard status == noErr else { return nil }
        return name as String
    }
}
