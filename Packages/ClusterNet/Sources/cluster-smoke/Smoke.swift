import ClusterNet
import ClusterProtocol
import Foundation

/// End-to-end Phase 1+2 smoke: register, join by code through a live relay,
/// converge rosters, then WALK — the joiner moves and the host's authoritative
/// snapshots must show it. Also asserts the negotiated transport matches
/// expectations (ADR 0002).
///
/// Env: RELAY_HOST, RELAY_CONTROL_PORT (7600), RELAY_UDP_PORT (7601),
///      RELAY_FINGERPRINT, CLUSTER_FORCE_TCP (optional, "1" = TCP-only mode).
@main
struct Smoke {
    static let walkSeconds = 1.2

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
                try? await Task.sleep(for: .seconds(25))
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }

        if outcome {
            print("SMOKE OK — lobby converged, joiner walked, transport=\(forceTCP ? "tcp" : "udp")")
            exit(0)
        } else {
            fail("smoke scenario did not complete in time")
        }
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

    static func runScenario(endpoint: RelayEndpoint, forceTCP: Bool) async -> Bool {
        do {
            let map = testMap()
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

            // Drive the joiner: learn spawn from the first snapshot containing
            // us, then walk right at legal speed; verify transport on the way.
            let walkResult = Task<Bool, Never> {
                var spawn: Vec2?
                var position: Vec2?
                var seq: UInt32 = 0
                var transportOK = false
                let inputInterval = 0.05

                for await event in joiner.events {
                    switch event {
                    case .transport(let usingUDP):
                        transportOK = (usingUDP == !forceTCP)
                        if !transportOK {
                            print("smoke: unexpected transport — usingUDP=\(usingUDP), forceTCP=\(forceTCP)")
                            return false
                        }
                    case .worldSnapshot(let snapshot):
                        guard let me = snapshot.players.first(where: { $0.id == joinerWireID }) else {
                            continue
                        }
                        if spawn == nil {
                            spawn = me.position
                            position = me.position
                            // Walk right for walkSeconds at the shared sim's legal pace.
                            let steps = Int(Smoke.walkSeconds / inputInterval)
                            for _ in 0..<steps {
                                seq += 1
                                position = MovementSim.step(
                                    position: position!, input: MoveInput(dirX: 1, dirY: 0),
                                    dt: inputInterval, collision: map.collision)
                                await joiner.sendInput(
                                    InputFrame(
                                        seq: seq, input: MoveInput(dirX: 1, dirY: 0),
                                        x: Float(position!.x), y: Float(position!.y)))
                                try? await Task.sleep(for: .milliseconds(50))
                            }
                        } else if let spawn, me.position.distance(to: spawn) > 1.5 {
                            print(
                                "smoke: host accepted the walk — moved "
                                    + String(format: "%.2f", me.position.distance(to: spawn))
                                    + " tiles, transportOK=\(transportOK)")
                            return transportOK
                        }
                    case .denied(let reason), .ended(let reason):
                        print("smoke: joiner ended early: \(reason)")
                        return false
                    default:
                        break
                    }
                }
                return false
            }

            let walked = await walkResult.value
            await joiner.leave()
            await host.stop()
            return walked
        } catch {
            print("smoke: error \(error)")
            return false
        }
    }

    static func fail(_ message: String) -> Never {
        print("SMOKE FAILED — \(message)")
        exit(1)
    }
}
