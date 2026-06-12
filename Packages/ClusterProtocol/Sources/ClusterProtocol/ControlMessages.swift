import Foundation

/// Who is opening this control connection to the relay.
public enum ControlRole: UInt8, Sendable {
    /// Persistent host connection: registers a session, receives incomingPair.
    case host = 1
    /// Joiner connection: looks up a code, then becomes one end of the splice.
    case joiner = 2
    /// Host-side per-pair connection: attaches to a pairID, then becomes the
    /// other end of the splice.
    case attach = 3
    /// Connectivity Doctor: ping/pong only.
    case probe = 4
}

/// Messages on the app ↔ relay control plane (TLS, relay-terminated).
/// Nothing here is secret: codes, fingerprints, pair numbers. The invite
/// secret and identities travel only inside the end-to-end tunnel.
public enum ControlMessage: Equatable, Sendable {
    case clientHello(wireVersion: UInt16, role: ControlRole)
    case registerHost(sessionPublicKey: Data, spaceName: String)
    case registerAck(code: String)
    case joinRequest(code: String)
    case joinAccepted(pairID: UInt32, hostSessionKey: Data, spaceName: String)
    case joinDenied(reason: String)
    /// Relay → host control connection: a joiner is waiting; open an attach
    /// connection for this pair.
    case incomingPair(pairID: UInt32)
    case attach(pairID: UInt32)
    /// Relay → each leg of a pair right before spliceBegin: your UDP flow id
    /// and the bind token for your side (ADR 0002).
    case dataPlane(flowID: UInt32, token: UInt64)
    /// Relay → both legs of a pair: framing stops belonging to the relay after
    /// this message; the next bytes flow end-to-end.
    case spliceBegin
    /// Relay → host control connection: a pending pair's joiner vanished
    /// before the splice completed.
    case peerGone(pairID: UInt32)
    case ping(nonce: UInt64)
    case pong(nonce: UInt64)
    case error(message: String)

    private enum Kind: UInt8 {
        case clientHello = 1
        case registerHost = 2
        case registerAck = 3
        case joinRequest = 4
        case joinAccepted = 5
        case joinDenied = 6
        case incomingPair = 7
        case attach = 8
        case spliceBegin = 9
        case peerGone = 10
        case ping = 11
        case pong = 12
        case error = 13
        case dataPlane = 14
    }

    public func encoded() throws -> [UInt8] {
        var w = ByteWriter()
        switch self {
        case .clientHello(let wireVersion, let role):
            w.write(Kind.clientHello.rawValue)
            w.write(wireVersion)
            w.write(role.rawValue)
        case .registerHost(let key, let spaceName):
            w.write(Kind.registerHost.rawValue)
            try w.write(key)
            try w.write(spaceName)
        case .registerAck(let code):
            w.write(Kind.registerAck.rawValue)
            try w.write(code)
        case .joinRequest(let code):
            w.write(Kind.joinRequest.rawValue)
            try w.write(code)
        case .joinAccepted(let pairID, let key, let spaceName):
            w.write(Kind.joinAccepted.rawValue)
            w.write(pairID)
            try w.write(key)
            try w.write(spaceName)
        case .joinDenied(let reason):
            w.write(Kind.joinDenied.rawValue)
            try w.write(reason)
        case .incomingPair(let pairID):
            w.write(Kind.incomingPair.rawValue)
            w.write(pairID)
        case .attach(let pairID):
            w.write(Kind.attach.rawValue)
            w.write(pairID)
        case .dataPlane(let flowID, let token):
            w.write(Kind.dataPlane.rawValue)
            w.write(flowID)
            w.write(token)
        case .spliceBegin:
            w.write(Kind.spliceBegin.rawValue)
        case .peerGone(let pairID):
            w.write(Kind.peerGone.rawValue)
            w.write(pairID)
        case .ping(let nonce):
            w.write(Kind.ping.rawValue)
            w.write(nonce)
        case .pong(let nonce):
            w.write(Kind.pong.rawValue)
            w.write(nonce)
        case .error(let message):
            w.write(Kind.error.rawValue)
            try w.write(message)
        }
        return w.bytes
    }

    public init(decoding bytes: [UInt8]) throws {
        var r = ByteReader(bytes)
        guard let kind = Kind(rawValue: try r.readUInt8()) else { throw CodecError.invalidValue }
        switch kind {
        case .clientHello:
            let version = try r.readUInt16()
            guard let role = ControlRole(rawValue: try r.readUInt8()) else {
                throw CodecError.invalidValue
            }
            self = .clientHello(wireVersion: version, role: role)
        case .registerHost:
            self = .registerHost(sessionPublicKey: try r.readData(), spaceName: try r.readString())
        case .registerAck:
            self = .registerAck(code: try r.readString())
        case .joinRequest:
            self = .joinRequest(code: try r.readString())
        case .joinAccepted:
            self = .joinAccepted(
                pairID: try r.readUInt32(),
                hostSessionKey: try r.readData(),
                spaceName: try r.readString()
            )
        case .joinDenied:
            self = .joinDenied(reason: try r.readString())
        case .incomingPair:
            self = .incomingPair(pairID: try r.readUInt32())
        case .attach:
            self = .attach(pairID: try r.readUInt32())
        case .dataPlane:
            self = .dataPlane(flowID: try r.readUInt32(), token: try r.readUInt64())
        case .spliceBegin:
            self = .spliceBegin
        case .peerGone:
            self = .peerGone(pairID: try r.readUInt32())
        case .ping:
            self = .ping(nonce: try r.readUInt64())
        case .pong:
            self = .pong(nonce: try r.readUInt64())
        case .error:
            self = .error(message: try r.readString())
        }
    }
}
