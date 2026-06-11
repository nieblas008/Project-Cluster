import ClusterProtocol
import CryptoKit
import Foundation
import Network

public enum ConnectionError: Error, Equatable {
    /// TLS pin mismatch — carries what the relay actually presented so the
    /// Doctor can show "expected … / got …".
    case pinMismatch(actual: String)
    case failed(String)
    case closed
    case protocolViolation
}

/// One TLS+TCP connection to the relay carrying length-prefixed frames.
/// After `spliceBegin` the very same connection *is* the end-to-end tunnel —
/// the framing never changes, only who's on the other end and what's inside.
public actor FrameConnection {
    private let connection: NWConnection
    private let pinObserved: PinObservation
    public let incomingFrames: AsyncThrowingStream<[UInt8], Error>
    private let framesContinuation: AsyncThrowingStream<[UInt8], Error>.Continuation
    private var assembler = FrameAssembler()
    private var started = false

    /// The verify block runs on a TLS queue; it records what it saw so a
    /// handshake failure can be attributed to the pin specifically.
    private final class PinObservation: @unchecked Sendable {
        private let lock = NSLock()
        private var _actual: String?
        var actual: String? {
            get { lock.withLock { _actual } }
            set { lock.withLock { _actual = newValue } }
        }
    }

    public init(endpoint: RelayEndpoint) {
        let observation = PinObservation()
        let expected = endpoint.certFingerprint
        let tlsOptions = NWProtocolTLS.Options()
        sec_protocol_options_set_verify_block(
            tlsOptions.securityProtocolOptions,
            { _, trustRef, complete in
                let trust = sec_trust_copy_ref(trustRef).takeRetainedValue()
                guard
                    let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
                    let leaf = chain.first
                else {
                    complete(false)
                    return
                }
                let der = SecCertificateCopyData(leaf) as Data
                let fingerprint = SHA256.hash(data: der).map { String(format: "%02x", $0) }.joined()
                observation.actual = fingerprint
                complete(fingerprint == expected)
            },
            DispatchQueue(label: "cluster.tls.verify")
        )
        self.pinObserved = observation

        let parameters = NWParameters(tls: tlsOptions)
        self.connection = NWConnection(
            host: NWEndpoint.Host(endpoint.host),
            port: NWEndpoint.Port(rawValue: endpoint.controlPort)!,
            using: parameters
        )
        (incomingFrames, framesContinuation) = AsyncThrowingStream.makeStream()
    }

    /// Connects and starts the frame read loop.
    public func start() async throws {
        guard !started else { return }
        started = true

        let resumer = OneShotResumer()
        let observation = pinObserved
        connection.stateUpdateHandler = { [framesContinuation] state in
            switch state {
            case .ready:
                resumer.resume(.success(()))
            case .failed(let error):
                let mapped: ConnectionError =
                    observation.actual.flatMap { actual in
                        // A recorded-but-rejected pin means *we* refused them.
                        error.isTLSHandshakeFailure ? .pinMismatch(actual: actual) : nil
                    } ?? .failed(error.localizedDescription)
                resumer.resume(.failure(mapped))
                framesContinuation.finish(throwing: mapped)
            case .cancelled:
                resumer.resume(.failure(ConnectionError.closed))
                framesContinuation.finish()
            default:
                break
            }
        }
        connection.start(queue: DispatchQueue(label: "cluster.connection"))
        try await resumer.wait()
        receiveNext()
    }

    private nonisolated func receiveNext() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) {
            [weak self] data, _, isComplete, error in
            guard let self else { return }
            Task {
                let alive = await self.ingest(data: data, isComplete: isComplete, error: error)
                // Ordering: the next receive is requested only after this chunk
                // is fully assembled, so frames can never interleave.
                if alive { self.receiveNext() }
            }
        }
    }

    private func ingest(data: Data?, isComplete: Bool, error: NWError?) -> Bool {
        if let data, !data.isEmpty {
            assembler.append([UInt8](data))
            do {
                while let payload = try assembler.next() {
                    framesContinuation.yield(payload)
                }
            } catch {
                framesContinuation.finish(throwing: ConnectionError.protocolViolation)
                connection.cancel()
                return false
            }
        }
        if isComplete || error != nil {
            framesContinuation.finish(
                throwing: error.map { ConnectionError.failed($0.localizedDescription) })
            connection.cancel()
            return false
        }
        return true
    }

    public func send(frame payload: [UInt8]) async throws {
        let bytes = try Frame.encode(payload)
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.send(
                content: Data(bytes),
                completion: .contentProcessed { error in
                    if let error {
                        cont.resume(throwing: ConnectionError.failed(error.localizedDescription))
                    } else {
                        cont.resume()
                    }
                })
        }
    }

    public func send(_ message: ControlMessage) async throws {
        try await send(frame: message.encoded())
    }

    public func cancel() {
        connection.cancel()
    }
}

/// stateUpdateHandler fires many times; the start() continuation must resume
/// exactly once.
private final class OneShotResumer: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    private var result: Result<Void, Error>?

    func resume(_ result: Result<Void, Error>) {
        lock.withLock {
            if let continuation {
                self.continuation = nil
                continuation.resume(with: result)
            } else if self.result == nil {
                self.result = result
            }
        }
    }

    func wait() async throws {
        try await withCheckedThrowingContinuation { cont in
            lock.withLock {
                if let result {
                    cont.resume(with: result)
                } else {
                    continuation = cont
                }
            }
        }
    }
}

extension NWError {
    fileprivate var isTLSHandshakeFailure: Bool {
        if case .tls = self { return true }
        return false
    }
}
