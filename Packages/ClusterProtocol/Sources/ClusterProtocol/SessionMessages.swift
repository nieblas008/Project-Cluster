import Foundation

/// One row of the lobby roster as the host broadcasts it.
public struct RosterEntry: Equatable, Sendable {
    /// Hex public identity key — stable per player.
    public var playerID: String
    public var displayName: String
    public var avatarPreset: String
    public var isOnline: Bool

    public init(playerID: String, displayName: String, avatarPreset: String, isOnline: Bool) {
        self.playerID = playerID
        self.displayName = displayName
        self.avatarPreset = avatarPreset
        self.isOnline = isOnline
    }
}

/// Messages inside the end-to-end tunnel (after the handshake; every frame is
/// sealed). The relay never sees these. Joiner→host and host→joiner share one
/// message space.
public enum SessionMessage: Equatable, Sendable {
    /// Joiner introduces itself. `signature` is the identity key's signature
    /// over "cluster-join/1" + the handshake transcript hash, binding this
    /// identity to this specific encrypted channel (no replay onto another).
    case joinHello(
        identityKey: Data, displayName: String, avatarPreset: String,
        inviteSecret: String, signature: Data)
    /// Host: you're in. Roster follows and stays updated.
    case welcome(spaceName: String, roster: [RosterEntry])
    /// Host: first-time identity — a human is looking at an approve dialog.
    case knockPending
    case denied(reason: String)
    case rosterUpdate(roster: [RosterEntry])
    /// Either side: clean goodbye before closing.
    case leave

    private enum Kind: UInt8 {
        case joinHello = 1
        case welcome = 2
        case knockPending = 3
        case denied = 4
        case rosterUpdate = 5
        case leave = 6
    }

    public func encoded() throws -> [UInt8] {
        var w = ByteWriter()
        switch self {
        case .joinHello(let identityKey, let displayName, let avatarPreset, let inviteSecret, let signature):
            w.write(Kind.joinHello.rawValue)
            try w.write(identityKey)
            try w.write(displayName)
            try w.write(avatarPreset)
            try w.write(inviteSecret)
            try w.write(signature)
        case .welcome(let spaceName, let roster):
            w.write(Kind.welcome.rawValue)
            try w.write(spaceName)
            try Self.write(roster: roster, to: &w)
        case .knockPending:
            w.write(Kind.knockPending.rawValue)
        case .denied(let reason):
            w.write(Kind.denied.rawValue)
            try w.write(reason)
        case .rosterUpdate(let roster):
            w.write(Kind.rosterUpdate.rawValue)
            try Self.write(roster: roster, to: &w)
        case .leave:
            w.write(Kind.leave.rawValue)
        }
        return w.bytes
    }

    public init(decoding bytes: [UInt8]) throws {
        var r = ByteReader(bytes)
        guard let kind = Kind(rawValue: try r.readUInt8()) else { throw CodecError.invalidValue }
        switch kind {
        case .joinHello:
            self = .joinHello(
                identityKey: try r.readData(),
                displayName: try r.readString(),
                avatarPreset: try r.readString(),
                inviteSecret: try r.readString(),
                signature: try r.readData()
            )
        case .welcome:
            self = .welcome(spaceName: try r.readString(), roster: try Self.readRoster(from: &r))
        case .knockPending:
            self = .knockPending
        case .denied:
            self = .denied(reason: try r.readString())
        case .rosterUpdate:
            self = .rosterUpdate(roster: try Self.readRoster(from: &r))
        case .leave:
            self = .leave
        }
    }

    private static func write(roster: [RosterEntry], to w: inout ByteWriter) throws {
        guard roster.count <= Int(UInt16.max) else { throw CodecError.invalidValue }
        w.write(UInt16(roster.count))
        for entry in roster {
            try w.write(entry.playerID)
            try w.write(entry.displayName)
            try w.write(entry.avatarPreset)
            w.write(entry.isOnline)
        }
    }

    private static func readRoster(from r: inout ByteReader) throws -> [RosterEntry] {
        let count = Int(try r.readUInt16())
        var roster: [RosterEntry] = []
        roster.reserveCapacity(count)
        for _ in 0..<count {
            roster.append(
                RosterEntry(
                    playerID: try r.readString(),
                    displayName: try r.readString(),
                    avatarPreset: try r.readString(),
                    isOnline: try r.readBool()
                ))
        }
        return roster
    }
}

/// Context string for the joinHello signature — versioned so future handshake
/// revisions can't be cross-replayed.
public enum SessionSigning {
    public static let joinContext = "cluster-join/1"
}
