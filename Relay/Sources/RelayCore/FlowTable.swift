import ClusterProtocol
import Foundation
import NIOConcurrencyHelpers
import NIOCore

/// UDP data plane state (ADR 0002): per-pair flows, bound to the two sides'
/// observed addresses by token. No keys, no payloads — addresses and counters
/// only, and it forgets idle flows by itself.
public final class FlowTable: Sendable {
    public enum Side: Sendable {
        case host
        case joiner
    }

    struct Flow {
        let hostToken: UInt64
        let joinerToken: UInt64
        var hostAddress: SocketAddress?
        var joinerAddress: SocketAddress?
        var lastActivity: NIODeadline
    }

    private struct State {
        var flows: [UInt32: Flow] = [:]
        var nextFlowID: UInt32 = 1
    }

    private let state = NIOLockedValueBox(State())

    /// Flows idle longer than this get swept.
    public static let idleExpiry = TimeAmount.seconds(120)

    public init() {}

    public func createFlow() -> (flowID: UInt32, hostToken: UInt64, joinerToken: UInt64) {
        let hostToken = UInt64.random(in: UInt64.min...UInt64.max)
        let joinerToken = UInt64.random(in: UInt64.min...UInt64.max)
        return state.withLockedValue { s in
            let flowID = s.nextFlowID
            s.nextFlowID &+= 1
            s.flows[flowID] = Flow(
                hostToken: hostToken, joinerToken: joinerToken,
                hostAddress: nil, joinerAddress: nil, lastActivity: .now())
            return (flowID, hostToken, joinerToken)
        }
    }

    /// Token match binds (or re-binds — NATs rebind ports) a side's address.
    /// Returns the side on success, nil on unknown flow/bad token.
    public func bind(flowID: UInt32, token: UInt64, address: SocketAddress) -> Side? {
        state.withLockedValue { s in
            guard var flow = s.flows[flowID] else { return nil }
            defer { s.flows[flowID] = flow }
            flow.lastActivity = .now()
            if token == flow.hostToken {
                flow.hostAddress = address
                return .host
            }
            if token == flow.joinerToken {
                flow.joinerAddress = address
                return .joiner
            }
            return nil
        }
    }

    /// Where should a data packet on this flow, from this address, go?
    public func destination(flowID: UInt32, from source: SocketAddress) -> SocketAddress? {
        state.withLockedValue { s in
            guard var flow = s.flows[flowID] else { return nil }
            defer { s.flows[flowID] = flow }
            flow.lastActivity = .now()
            if source == flow.hostAddress {
                return flow.joinerAddress
            }
            if source == flow.joinerAddress {
                return flow.hostAddress
            }
            return nil
        }
    }

    /// Drops idle flows; returns how many were removed (for logging).
    public func sweep(now: NIODeadline = .now()) -> Int {
        state.withLockedValue { s in
            let before = s.flows.count
            s.flows = s.flows.filter { now - $0.value.lastActivity < Self.idleExpiry }
            return before - s.flows.count
        }
    }

    public var flowCount: Int {
        state.withLockedValue { $0.flows.count }
    }
}
