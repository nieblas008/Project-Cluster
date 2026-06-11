import Foundation
import NIOConcurrencyHelpers
import NIOCore

/// All relay state, in memory, gone on restart — by design (PLAN §2).
/// Channels are NIO `Channel`s, safe to write/close from any thread.
public final class SessionRegistry: Sendable {
    public struct Session: Sendable {
        public let code: String
        public let spaceName: String
        public let hostSessionKey: Data
        public let hostChannel: Channel
    }

    public struct PendingPair: Sendable {
        public let pairID: UInt32
        public let code: String
        public let joinerChannel: Channel
    }

    private struct State {
        var sessionsByCode: [String: Session] = [:]
        var codeByHostChannel: [ObjectIdentifier: String] = [:]
        var pendingPairs: [UInt32: PendingPair] = [:]
        var nextPairID: UInt32 = 1
    }

    private let state = NIOLockedValueBox(State())

    public init() {}

    /// Unambiguous alphabet (no 0/O, 1/I/L) — codes get read aloud on calls.
    static let codeAlphabet = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")

    static func makeCode() -> String {
        String((0..<6).map { _ in codeAlphabet.randomElement()! })
    }

    public func register(spaceName: String, hostSessionKey: Data, hostChannel: Channel) -> String {
        state.withLockedValue { s in
            var code = Self.makeCode()
            while s.sessionsByCode[code] != nil {
                code = Self.makeCode()
            }
            s.sessionsByCode[code] = Session(
                code: code, spaceName: spaceName,
                hostSessionKey: hostSessionKey, hostChannel: hostChannel)
            s.codeByHostChannel[ObjectIdentifier(hostChannel)] = code
            return code
        }
    }

    public func session(code: String) -> Session? {
        state.withLockedValue { $0.sessionsByCode[code.uppercased()] }
    }

    /// Parks a joiner channel against a session, handing back the pair id.
    public func createPair(code: String, joinerChannel: Channel) -> (pairID: UInt32, session: Session)? {
        state.withLockedValue { s in
            guard let session = s.sessionsByCode[code.uppercased()] else { return nil }
            let pairID = s.nextPairID
            s.nextPairID &+= 1
            s.pendingPairs[pairID] = PendingPair(
                pairID: pairID, code: session.code, joinerChannel: joinerChannel)
            return (pairID, session)
        }
    }

    /// Consumed by the host's attach connection; a pair can be claimed once.
    public func claimPair(pairID: UInt32) -> PendingPair? {
        state.withLockedValue { $0.pendingPairs.removeValue(forKey: pairID) }
    }

    /// Timeout / joiner-died path.
    public func cancelPair(pairID: UInt32) -> PendingPair? {
        state.withLockedValue { $0.pendingPairs.removeValue(forKey: pairID) }
    }

    /// Host control connection died: drop the session and surface any joiners
    /// still parked against it so the caller can deny + close them.
    public func unregisterHost(channel: Channel) -> (code: String, orphanedPairs: [PendingPair])? {
        state.withLockedValue { s in
            guard let code = s.codeByHostChannel.removeValue(forKey: ObjectIdentifier(channel)) else {
                return nil
            }
            s.sessionsByCode.removeValue(forKey: code)
            let orphaned = s.pendingPairs.values.filter { $0.code == code }
            for pair in orphaned {
                s.pendingPairs.removeValue(forKey: pair.pairID)
            }
            return (code, Array(orphaned))
        }
    }

    public var sessionCount: Int {
        state.withLockedValue { $0.sessionsByCode.count }
    }
}
