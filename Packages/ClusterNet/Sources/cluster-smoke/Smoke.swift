import ClusterNet
import ClusterProtocol
import Foundation

/// End-to-end Phase 1 smoke: register a session, join it by code through a
/// live relay, and require both sides to see a two-person roster.
///
/// Env: RELAY_HOST, RELAY_CONTROL_PORT (7600), RELAY_UDP_PORT (7601),
///      RELAY_FINGERPRINT (sha256 hex of the relay cert DER).
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

        let outcome = await withTaskGroup(of: Bool.self) { group in
            group.addTask { await runScenario(endpoint: endpoint) }
            group.addTask {
                try? await Task.sleep(for: .seconds(20))
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }

        if outcome {
            print("SMOKE OK — host + joiner saw each other through the relay")
            exit(0)
        } else {
            fail("smoke scenario did not complete in time")
        }
    }

    static func runScenario(endpoint: RelayEndpoint) async -> Bool {
        do {
            let hostIdentity = try IdentityManager.loadOrCreate(store: InMemorySecretStore())
            let joinerIdentity = try IdentityManager.loadOrCreate(store: InMemorySecretStore())

            let host = HostSession(
                endpoint: endpoint,
                identity: hostIdentity,
                directory: InMemoryDirectory(autoApprove: true),
                spaceName: "Smoke Mansion",
                hostDisplayName: "Hostie",
                hostAvatarPreset: "default"
            )
            let code = try await host.start()
            print("smoke: hosting with code \(code)")

            let joiner = JoinSession(
                endpoint: endpoint, identity: joinerIdentity,
                displayName: "Smokey", avatarPreset: "default")
            await joiner.start(code: code)

            var joinerSawBoth = false
            var hostSawBoth = false

            await withTaskGroup(of: Bool.self) { group in
                group.addTask {
                    for await event in joiner.events {
                        switch event {
                        case .welcomed(let space, let roster):
                            print("smoke: joiner welcomed to \(space), roster=\(roster.count)")
                            if roster.count >= 2 { return true }
                        case .rosterChanged(let roster) where roster.count >= 2:
                            return true
                        case .denied(let reason), .ended(let reason):
                            print("smoke: joiner ended early: \(reason)")
                            return false
                        default:
                            break
                        }
                    }
                    return false
                }
                group.addTask {
                    for await event in host.events {
                        switch event {
                        case .rosterChanged(let roster) where roster.count >= 2:
                            print("smoke: host roster reached \(roster.count)")
                            return true
                        case .ended(let reason):
                            print("smoke: host ended early: \(reason)")
                            return false
                        default:
                            break
                        }
                    }
                    return false
                }
                for await result in group.prefix(2) {
                    if joinerSawBoth == false {
                        joinerSawBoth = result
                    } else {
                        hostSawBoth = result
                    }
                }
            }

            await joiner.leave()
            await host.stop()
            return joinerSawBoth && hostSawBoth
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
