import ClusterProtocol
import CryptoKit
import Foundation
import Network

/// Seals world payloads for the UDP plane: nonce = explicit sequence number,
/// AAD = flowID. The receive side accepts only ascending sequence numbers —
/// replays and stragglers drop, which is exactly right for latest-wins traffic.
public struct DatagramCipher: Sendable {
    private let key: SymmetricKey
    private let flowAAD: Data
    private var sendSeq: UInt64 = 0
    private var highestReceivedSeq: UInt64 = 0

    public init(key: SymmetricKey, flowID: UInt32) {
        self.key = key
        var w = ByteWriter()
        w.write(flowID)
        self.flowAAD = Data(w.bytes)
    }

    private static func nonce(for seq: UInt64) -> ChaChaPoly.Nonce {
        var data = Data(repeating: 0, count: 4)
        withUnsafeBytes(of: seq.littleEndian) { data.append(contentsOf: $0) }
        return try! ChaChaPoly.Nonce(data: data)
    }

    public mutating func seal(_ plaintext: [UInt8]) throws -> (seq: UInt64, ciphertext: [UInt8]) {
        sendSeq += 1
        let box = try ChaChaPoly.seal(
            Data(plaintext), using: key, nonce: Self.nonce(for: sendSeq), authenticating: flowAAD)
        return (sendSeq, Array(box.ciphertext + box.tag))
    }

    /// nil = drop silently (replay, stale, or tampered — none are worth a log line per packet).
    public mutating func open(seq: UInt64, ciphertext: [UInt8]) -> [UInt8]? {
        guard seq > highestReceivedSeq, ciphertext.count >= 16 else { return nil }
        let body = Data(ciphertext[0..<ciphertext.count - 16])
        let tag = Data(ciphertext[(ciphertext.count - 16)...])
        guard
            let box = try? ChaChaPoly.SealedBox(
                nonce: Self.nonce(for: seq), ciphertext: body, tag: tag),
            let plaintext = try? ChaChaPoly.open(box, using: key, authenticating: flowAAD)
        else { return nil }
        highestReceivedSeq = seq
        return Array(plaintext)
    }
}

/// One side's UDP path to the relay for one flow: binds with the token the
/// control plane handed out, then carries sealed world payloads. `start()`
/// returning false *is* the UDP probe — the caller falls back to TCP (ADR 0002).
public actor DatagramChannel {
    private let connection: NWConnection
    private let flowID: UInt32
    private let token: UInt64
    private var sendCipher: DatagramCipher
    private var receiveCipher: DatagramCipher

    public nonisolated let incoming: AsyncStream<[UInt8]>
    private let incomingContinuation: AsyncStream<[UInt8]>.Continuation

    private var bindAck: CheckedContinuation<Void, Never>?
    private var bound = false

    public init(
        endpoint: RelayEndpoint, flowID: UInt32, token: UInt64,
        sendKey: SymmetricKey, receiveKey: SymmetricKey
    ) {
        self.connection = NWConnection(
            host: NWEndpoint.Host(endpoint.host),
            port: NWEndpoint.Port(rawValue: endpoint.udpPort)!,
            using: .udp
        )
        self.flowID = flowID
        self.token = token
        self.sendCipher = DatagramCipher(key: sendKey, flowID: flowID)
        self.receiveCipher = DatagramCipher(key: receiveKey, flowID: flowID)
        (incoming, incomingContinuation) = AsyncStream.makeStream(
            bufferingPolicy: .bufferingNewest(32))
    }

    /// Binds against the relay: up to 3 attempts, ~1 s apart. True = UDP works
    /// from this network; false = use the tunnel road instead.
    public func start() async -> Bool {
        connection.start(queue: DispatchQueue(label: "cluster.datagram"))
        receiveNext()

        let bind = DatagramWire.encodeBind(flowID: flowID, token: token)
        for _ in 0..<3 {
            connection.send(content: Data(bind), completion: .contentProcessed { _ in })
            let acked = await withTaskGroup(of: Bool.self) { group in
                group.addTask {
                    await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                        Task { await self.setBindAck(cont) }
                    }
                    return true
                }
                group.addTask {
                    try? await Task.sleep(for: .milliseconds(1000))
                    return false
                }
                let first = await group.next() ?? false
                group.cancelAll()
                await self.clearBindAck()
                return first
            }
            if acked {
                bound = true
                return true
            }
        }
        connection.cancel()
        return false
    }

    private func setBindAck(_ cont: CheckedContinuation<Void, Never>) {
        if bound {
            cont.resume()
            return
        }
        bindAck = cont
    }

    private func clearBindAck() {
        bindAck?.resume()
        bindAck = nil
    }

    private nonisolated func receiveNext() {
        connection.receiveMessage { [weak self] data, _, _, error in
            guard let self, error == nil else { return }
            Task {
                await self.ingest(data.map { [UInt8]($0) } ?? [])
                self.receiveNext()
            }
        }
    }

    private func ingest(_ bytes: [UInt8]) {
        if let bind = DatagramWire.decodeBind(bytes), bind.flowID == flowID {
            bound = true
            bindAck?.resume()
            bindAck = nil
            return
        }
        guard
            let data = DatagramWire.decodeData(bytes),
            data.flowID == flowID,
            let plaintext = receiveCipher.open(seq: data.seq, ciphertext: data.ciphertext)
        else { return }
        incomingContinuation.yield(plaintext)
    }

    public func send(_ payload: [UInt8]) {
        guard bound else { return }
        guard let (seq, ciphertext) = try? sendCipher.seal(payload) else { return }
        let packet = DatagramWire.encodeData(flowID: flowID, seq: seq, ciphertext: ciphertext)
        connection.send(content: Data(packet), completion: .contentProcessed { _ in })
    }

    public func cancel() {
        incomingContinuation.finish()
        connection.cancel()
    }
}
