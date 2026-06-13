import AVFoundation
import ClusterNet
import ClusterProtocol
import ClusterVoice
import Foundation

/// End-to-end smoke, Phases 1–3: join by code through a live relay, converge
/// rosters, WALK (host-validated movement), then TALK (synthetic Opus frames
/// through the host's proximity fan-out, decoded on arrival). Runs against
/// both transports via CLUSTER_FORCE_TCP.
@main
struct Smoke {
    static func main() async {
        let env = ProcessInfo.processInfo.environment
        guard let host = env["RELAY_HOST"], let fingerprint = env["RELAY_FINGERPRINT"] else {
            fail("RELAY_HOST and RELAY_FINGERPRINT must be set")
        }
        let endpoint = RelayEndpoint(
            host: host,
            controlPort: UInt16(env["RELAY_CONTROL_PORT"] ?? "7600") ?? 7600,
            udpPort: UInt16(env["RELAY_UDP_PORT"] ?? "7601") ?? 7601,
            certFingerprint: fingerprint
        )
        let forceTCP = env["CLUSTER_FORCE_TCP"] == "1"

        let outcome = await withTaskGroup(of: Bool.self) { group in
            group.addTask { await runScenario(endpoint: endpoint, forceTCP: forceTCP) }
            group.addTask {
                try? await Task.sleep(for: .seconds(30))
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }

        if outcome {
            print(
                "SMOKE OK — roster, walk, voice, and status all good, "
                    + "transport=\(forceTCP ? "tcp" : "udp")")
            exit(0)
        } else {
            fail("smoke scenario did not complete in time")
        }
    }

    /// Shared scoreboard between the event-consumer tasks and the main flow.
    final class Results: @unchecked Sendable {
        private let lock = NSLock()
        private var _walked = false
        private var _transportOK: Bool?
        private var _hostVoiceFrames = 0
        private var _joinerVoiceFrames = 0
        private var _joinerStatusOnHost: PlayerStatus?
        private var _failure: String?

        var walked: Bool { lock.withLock { _walked } }
        var transportOK: Bool? { lock.withLock { _transportOK } }
        var hostVoiceFrames: Int { lock.withLock { _hostVoiceFrames } }
        var joinerVoiceFrames: Int { lock.withLock { _joinerVoiceFrames } }
        var joinerStatusOnHost: PlayerStatus? { lock.withLock { _joinerStatusOnHost } }
        var failure: String? { lock.withLock { _failure } }

        func markWalked() { lock.withLock { _walked = true } }
        func markTransport(ok: Bool) { lock.withLock { _transportOK = ok } }
        func addHostVoiceFrame() { lock.withLock { _hostVoiceFrames += 1 } }
        func addJoinerVoiceFrame() { lock.withLock { _joinerVoiceFrames += 1 } }
        func setJoinerStatusOnHost(_ s: PlayerStatus) { lock.withLock { _joinerStatusOnHost = s } }
        func markFailure(_ reason: String) { lock.withLock { _failure = _failure ?? reason } }
    }

    /// 12×8 room: border walls (gid 2 collides), spawn at tile (3,3).
    static func testMap() -> WorldMap {
        var data = [UInt32](repeating: 0, count: 96)
        for x in 0..<12 {
            data[x] = 2
            data[84 + x] = 2
        }
        for y in 0..<8 {
            data[y * 12] = 2
            data[y * 12 + 11] = 2
        }
        let json = """
            {"width":12,"height":8,"tilewidth":32,
             "layers":[
               {"name":"floor","type":"tilelayer","data":\(Array(repeating: 1, count: 96))},
               {"name":"walls","type":"tilelayer","data":\(data)},
               {"name":"objects","type":"objectgroup","objects":[
                 {"name":"spawn","type":"spawn","x":96.0,"y":96.0}]}],
             "tilesets":[{"firstgid":1,"tiles":[
               {"id":1,"properties":[{"name":"collides","type":"bool","value":true}]}]}]}
            """
        return try! TiledMapLoader.load(data: Data(json.utf8))
    }

    static func sineFrame() -> AVAudioPCMBuffer {
        let format = AVAudioFormat(
            standardFormatWithSampleRate: VoiceFormat.sampleRate, channels: 1)!
        let buffer = AVAudioPCMBuffer(
            pcmFormat: format, frameCapacity: AVAudioFrameCount(VoiceFormat.samplesPerFrame))!
        buffer.frameLength = AVAudioFrameCount(VoiceFormat.samplesPerFrame)
        for i in 0..<VoiceFormat.samplesPerFrame {
            buffer.floatChannelData![0][i] =
                sin(Float(i) * 2 * .pi * 440 / Float(VoiceFormat.sampleRate)) * 0.5
        }
        return buffer
    }

    static func runScenario(endpoint: RelayEndpoint, forceTCP: Bool) async -> Bool {
        do {
            let map = testMap()
            let results = Results()
            let hostIdentity = try IdentityManager.loadOrCreate(store: InMemorySecretStore())
            let joinerIdentity = try IdentityManager.loadOrCreate(store: InMemorySecretStore())
            let joinerWireID = PlayerWireID.prefix(fromHexID: joinerIdentity.playerID)

            let host = HostSession(
                endpoint: endpoint,
                identity: hostIdentity,
                directory: InMemoryDirectory(autoApprove: true),
                spaceName: "Smoke Mansion",
                hostDisplayName: "Hostie",
                hostAvatarPreset: "default",
                map: map,
                allowUDP: !forceTCP
            )
            let code = try await host.start()
            print("smoke: hosting with code \(code)")

            let joiner = JoinSession(
                endpoint: endpoint, identity: joinerIdentity,
                displayName: "Smokey", avatarPreset: "default",
                mapHash: map.contentHash, preferUDP: !forceTCP)
            await joiner.start(code: code)

            // Host events: voice frames from the joiner must decode with energy.
            let hostConsumer = Task {
                let decoder = try? OpusDecoder()
                for await event in host.events {
                    switch event {
                    case .voiceReceived(let speakerID, _, let opus):
                        if speakerID == joinerWireID,
                            let pcm = try? decoder?.decode(opus), pcm.rmsLevel > 0.01
                        {
                            results.addHostVoiceFrame()
                        }
                    case .rosterChanged(let roster):
                        if let joiner = roster.first(where: {
                            PlayerWireID.prefix(fromHexID: $0.playerID) == joinerWireID
                        }) {
                            results.setJoinerStatusOnHost(joiner.status)
                        }
                    case .ended(let reason):
                        results.markFailure("host ended: \(reason)")
                        return
                    default:
                        break
                    }
                }
            }

            // Joiner events: drive the walk, verify transport, collect voice.
            let joinerConsumer = Task {
                let decoder = try? OpusDecoder()
                var spawn: Vec2?
                var position: Vec2?
                var seq: UInt32 = 0

                for await event in joiner.events {
                    switch event {
                    case .transport(let usingUDP):
                        results.markTransport(ok: usingUDP == !forceTCP)
                    case .worldSnapshot(let snapshot):
                        guard let me = snapshot.players.first(where: { $0.id == joinerWireID })
                        else { continue }
                        if spawn == nil {
                            spawn = me.position
                            position = me.position
                            for _ in 0..<24 {
                                seq += 1
                                position = MovementSim.step(
                                    position: position!, input: MoveInput(dirX: 1, dirY: 0),
                                    dt: 0.05, collision: map.collision)
                                await joiner.sendInput(
                                    InputFrame(
                                        seq: seq, input: MoveInput(dirX: 1, dirY: 0),
                                        x: Float(position!.x), y: Float(position!.y)))
                                try? await Task.sleep(for: .milliseconds(50))
                            }
                        } else if let spawn, me.position.distance(to: spawn) > 1.5 {
                            results.markWalked()
                        }
                    case .voiceReceived(_, _, let opus):
                        if let pcm = try? decoder?.decode(opus), pcm.rmsLevel > 0.01 {
                            results.addJoinerVoiceFrame()
                        }
                    case .denied(let reason), .ended(let reason):
                        results.markFailure("joiner ended: \(reason)")
                        return
                    default:
                        break
                    }
                }
            }

            // Phase: walk.
            if !(await waitUntil { results.walked || results.failure != nil }) {
                print("smoke: walk did not complete — \(results.failure ?? "timeout")")
                return false
            }
            print("smoke: walk verified")

            // Phase: talk — both directions, 12 frames each at 20 ms cadence.
            let encoderJoiner = try OpusEncoder()
            let encoderHost = try OpusEncoder()
            for i in 1...12 {
                await joiner.sendVoice(seq: UInt32(i), opus: try encoderJoiner.encode(sineFrame()))
                await host.sendHostVoice(seq: UInt32(i), opus: try encoderHost.encode(sineFrame()))
                try? await Task.sleep(for: .milliseconds(20))
            }

            let voiceOK = await waitUntil {
                (results.hostVoiceFrames >= 6 && results.joinerVoiceFrames >= 6)
                    || results.failure != nil
            }
            print(
                "smoke: voice frames — host got \(results.hostVoiceFrames), "
                    + "joiner got \(results.joinerVoiceFrames)")

            // Phase: status — joiner goes DND, host's roster must reflect it.
            await joiner.setStatus(.dnd)
            let statusOK = await waitUntil { results.joinerStatusOnHost == .dnd }
            print("smoke: host sees joiner status = \(results.joinerStatusOnHost?.label ?? "nil")")

            hostConsumer.cancel()
            joinerConsumer.cancel()
            await joiner.leave()
            await host.stop()

            guard results.failure == nil else {
                print("smoke: failure — \(results.failure!)")
                return false
            }
            guard results.transportOK == true else {
                print("smoke: transport mismatch (forceTCP=\(forceTCP))")
                return false
            }
            return voiceOK && results.walked && statusOK
        } catch {
            print("smoke: error \(error)")
            return false
        }
    }

    static func waitUntil(
        timeout: Double = 8, _ condition: @escaping () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return condition()
    }

    static func fail(_ message: String) -> Never {
        print("SMOKE FAILED — \(message)")
        exit(1)
    }
}
