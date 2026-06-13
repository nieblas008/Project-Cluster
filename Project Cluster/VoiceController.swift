import ClusterProtocol
import ClusterVoice
import CoreAudio
import Foundation
import Observation
import QuartzCore

/// Binds a VoiceEngine to a session: mic frames out, speakers' frames in,
/// proximity gains from world snapshots, speaking indicators for the scene,
/// connection quality, and the HUD/Settings voice state.
@MainActor
@Observable
final class VoiceController {
    private let engine = VoiceEngine()

    private(set) var active = false
    private(set) var errorMessage: String?
    private(set) var micLevel: Float = 0
    private(set) var speakingIDs: Set<UInt64> = []
    private(set) var inputDevices: [VoiceEngine.InputDevice] = []
    private(set) var outputDevices: [VoiceEngine.InputDevice] = []
    private(set) var quality: ConnectionQuality = .good
    private(set) var stats = VoiceStats()

    var micMuted = false {
        didSet { engine.setMuted(micMuted) }
    }

    /// Push-to-talk vs open mic (persisted in AppModel, pushed in on start).
    var pushToTalk = false {
        didSet {
            engine.setPushToTalk(enabled: pushToTalk)
            if !pushToTalk { pttHeld = false }
        }
    }
    /// The HUD/key layer sets this while the talk key is held.
    var pttHeld = false {
        didSet { engine.setPushToTalkActive(pttHeld) }
    }

    var selectedInputDevice: AudioDeviceID? {
        didSet {
            guard let id = selectedInputDevice, id != oldValue else { return }
            do {
                try engine.setInputDevice(id)
            } catch {
                errorMessage = "Could not switch microphone: \(error.localizedDescription)"
            }
        }
    }

    var selectedOutputDevice: AudioDeviceID? {
        didSet {
            guard let id = selectedOutputDevice, id != oldValue else { return }
            engine.setOutputDevice(id)
        }
    }

    /// Scene hook — set by the lobby model that owns the WorldScene.
    var onSpeakingChanged: ((Set<UInt64>) -> Void)?

    private var localWireID: UInt64 = 0
    private var sendSeq: UInt32 = 0
    private var sendFrame: ((UInt32, Data) async -> Void)?
    private var lastFrameAt: [UInt64: Date] = [:]
    private var qualityEstimator = ConnectionQualityEstimator()
    private var decayTask: Task<Void, Never>?

    func start(localWireID: UInt64, pushToTalk: Bool, sendFrame: @escaping (UInt32, Data) async -> Void) {
        guard !active else { return }
        self.localWireID = localWireID
        self.sendFrame = sendFrame
        self.errorMessage = nil
        self.pushToTalk = pushToTalk
        inputDevices = VoiceEngine.availableInputDevices()
        outputDevices = VoiceEngine.availableOutputDevices()

        engine.onLevel = { [weak self] level in
            Task { @MainActor [weak self] in
                self?.micLevel = level
            }
        }
        engine.onEncodedFrame = { [weak self] opus, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.sendSeq &+= 1
                self.noteSpeaking(self.localWireID)
                let seq = self.sendSeq
                let send = self.sendFrame
                Task { await send?(seq, opus) }
            }
        }

        Task {
            do {
                try await engine.start()
                self.active = true
            } catch VoiceEngine.VoiceEngineError.microphonePermissionDenied {
                self.errorMessage =
                    "Microphone access denied — enable it in System Settings → "
                    + "Privacy & Security → Microphone, then re-enter the world."
            } catch {
                self.errorMessage = "Voice could not start: \(error.localizedDescription)"
            }
        }

        decayTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self else { return }
                self.decaySpeaking()
                self.quality = self.qualityEstimator.quality(now: CACurrentMediaTimeShim())
                self.stats = self.engine.snapshotStats()
            }
        }
    }

    func stop() {
        decayTask?.cancel()
        decayTask = nil
        engine.stop()
        active = false
        micLevel = 0
        speakingIDs = []
        lastFrameAt = [:]
        quality = .good
        qualityEstimator = ConnectionQualityEstimator()
        onSpeakingChanged?([])
    }

    func receive(speakerID: UInt64, seq: UInt32, opus: Data) {
        engine.enqueue(speakerID: speakerID, seq: seq, opus: opus)
        noteSpeaking(speakerID)
    }

    /// Each snapshot: distance → gain per remote speaker (PLAN §8 curve), and
    /// the arrival cadence drives the connection-quality read.
    func updateProximity(snapshot: WorldSnapshot) {
        qualityEstimator.recordArrival(at: CACurrentMediaTimeShim())
        guard let me = snapshot.players.first(where: { $0.id == localWireID }) else { return }
        for player in snapshot.players where player.id != localWireID {
            let gain = ProximityRules.standard.gain(
                atDistance: me.position.distance(to: player.position))
            engine.setVolume(speakerID: player.id, Float(gain))
        }
    }

    func speakerLeft(_ wireID: UInt64) {
        engine.removeSpeaker(wireID)
        lastFrameAt.removeValue(forKey: wireID)
    }

    private func noteSpeaking(_ id: UInt64) {
        lastFrameAt[id] = Date()
        if !speakingIDs.contains(id) {
            speakingIDs.insert(id)
            onSpeakingChanged?(speakingIDs)
        }
    }

    private func decaySpeaking() {
        let cutoff = Date().addingTimeInterval(-0.4)
        let quiet = speakingIDs.filter { (lastFrameAt[$0] ?? .distantPast) < cutoff }
        guard !quiet.isEmpty else { return }
        speakingIDs.subtract(quiet)
        onSpeakingChanged?(speakingIDs)
    }
}

/// A tiny indirection so the controller reads one monotonic clock everywhere.
func CACurrentMediaTimeShim() -> Double { CACurrentMediaTime() }
