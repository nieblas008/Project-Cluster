import ClusterProtocol
import Foundation
import Network

/// One row of the Doctor's report — plain language first (PLAN §14, Phase 1).
public struct DoctorCheck: Identifiable, Sendable {
    public enum Verdict: Sendable { case pass, fail, info }
    public let id = UUID()
    public var name: String
    public var verdict: Verdict
    public var detail: String
    public var remedy: String?
}

/// Run from any network — especially the host's work WiFi — to explain in
/// plain language whether this relay is reachable and how traffic will flow.
public enum ConnectivityDoctor {
    public static func run(endpoint: RelayEndpoint) async -> [DoctorCheck] {
        var checks: [DoctorCheck] = []

        guard endpoint.isConfigured else {
            return [
                DoctorCheck(
                    name: "Relay configuration", verdict: .fail,
                    detail: "No relay is configured.",
                    remedy: "Open Settings and enter the relay's IP and certificate fingerprint "
                        + "(printed by deploy/provision: see docs/runbooks/relay.md).")
            ]
        }

        // 1 + 2. TLS reachability + pin, then an authenticated protocol ping.
        let control = FrameConnection(endpoint: endpoint)
        do {
            let started = Date()
            try await control.start()
            try await control.send(.clientHello(wireVersion: ProtocolInfo.wireVersion, role: .probe))
            try await control.send(.ping(nonce: 7))

            var gotPong = false
            for try await frame in control.incomingFrames {
                if case .pong = try ControlMessage(decoding: frame) {
                    gotPong = true
                    break
                }
            }
            let rtt = Int(Date().timeIntervalSince(started) * 1000)
            checks.append(
                DoctorCheck(
                    name: "Relay control plane (TCP \(endpoint.controlPort))",
                    verdict: gotPong ? .pass : .fail,
                    detail: gotPong
                        ? "Reached, certificate pinned, protocol answered in \(rtt) ms."
                        : "Connected but the relay did not answer the ping.",
                    remedy: gotPong ? nil : "The relay may be an incompatible version — redeploy it."))
        } catch let error as ConnectionError {
            switch error {
            case .pinMismatch(let actual):
                checks.append(
                    DoctorCheck(
                        name: "Relay certificate", verdict: .fail,
                        detail: "The relay presented a different certificate "
                            + "(\(actual.prefix(16))…).",
                        remedy: "If the relay was redeployed with a new certificate, update the "
                            + "fingerprint in Settings. If not — stop and investigate; something "
                            + "is impersonating the relay."))
            default:
                checks.append(
                    DoctorCheck(
                        name: "Relay control plane (TCP \(endpoint.controlPort))", verdict: .fail,
                        detail: "Could not connect: \(error.humanReadable).",
                        remedy: "Check the relay is running (`docker compose ps` on the VPS), the "
                            + "IP in Settings is right, and the firewall allows "
                            + "\(endpoint.controlPort)/tcp. Some networks block unusual ports — "
                            + "try a phone hotspot to compare."))
            }
            await control.cancel()
            return checks
        } catch {
            checks.append(
                DoctorCheck(
                    name: "Relay control plane (TCP \(endpoint.controlPort))", verdict: .fail,
                    detail: "Unexpected error: \(error.humanReadable).",
                    remedy: "Relay and app versions may be out of sync — update both."))
            await control.cancel()
            return checks
        }
        await control.cancel()

        // 3. UDP reachability (movement/voice plane in Phase 2+).
        let udpResult = await probeUDPEcho(endpoint: endpoint)
        checks.append(udpResult)

        return checks
    }

    private static func probeUDPEcho(endpoint: RelayEndpoint) async -> DoctorCheck {
        let connection = NWConnection(
            host: NWEndpoint.Host(endpoint.host),
            port: NWEndpoint.Port(rawValue: endpoint.udpPort)!,
            using: .udp
        )
        defer { connection.cancel() }
        connection.start(queue: DispatchQueue(label: "cluster.doctor.udp"))

        let token = (0..<8).map { _ in UInt8.random(in: 0...255) }
        for _ in 0..<3 {
            connection.send(content: Data(token), completion: .contentProcessed { _ in })
            let echoed: Bool = await withCheckedContinuation { cont in
                let resumer = OneTimeFlag(cont)
                connection.receiveMessage { data, _, _, _ in
                    resumer.resume(data.map { [UInt8]($0) == token } ?? false)
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + 1.5) {
                    resumer.resume(false)
                }
            }
            if echoed {
                return DoctorCheck(
                    name: "UDP data plane (\(endpoint.udpPort)/udp)", verdict: .pass,
                    detail: "Datagrams flow both ways from this network.")
            }
        }
        return DoctorCheck(
            name: "UDP data plane (\(endpoint.udpPort)/udp)", verdict: .info,
            detail: "No UDP echo from this network — it likely blocks outbound UDP.",
            remedy: "Lobby and joining still work (they use TCP). Movement and voice (Phase 2+) "
                + "will use the TCP fallback from here: a bit more latency, still functional.")
    }
}

private final class OneTimeFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Bool, Never>?

    init(_ continuation: CheckedContinuation<Bool, Never>) {
        self.continuation = continuation
    }

    func resume(_ value: Bool) {
        lock.withLock {
            continuation?.resume(returning: value)
            continuation = nil
        }
    }
}
