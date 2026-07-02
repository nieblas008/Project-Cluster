import Foundation

/// One kart pad's live state. `ownerWireID == 0` means parked/free, and the
/// pose fields describe where it sits; while owned, the driver's snapshot is
/// the pose of record.
public struct KartInfo: Equatable, Sendable, Identifiable {
    public var id: String
    public var ownerWireID: UInt64
    public var x: Float
    public var y: Float
    public var heading: Float

    public init(id: String, ownerWireID: UInt64, x: Float, y: Float, heading: Float) {
        self.id = id
        self.ownerWireID = ownerWireID
        self.x = x
        self.y = y
        self.heading = heading
    }

    public var position: Vec2 { Vec2(x: Double(x), y: Double(y)) }
}

/// A leaderboard row: each player's personal-best lap.
public struct LapRecord: Equatable, Sendable {
    public var playerID: String
    public var displayName: String
    public var timeMs: UInt32

    public init(playerID: String, displayName: String, timeMs: UInt32) {
        self.playerID = playerID
        self.displayName = displayName
        self.timeMs = timeMs
    }
}

/// Full race world, broadcast on change (ADR 0006), desk-style.
public struct RaceState: Equatable, Sendable {
    public var karts: [KartInfo]
    public var leaderboard: [LapRecord]

    public init(karts: [KartInfo] = [], leaderboard: [LapRecord] = []) {
        self.karts = karts
        self.leaderboard = leaderboard
    }

    public func kart(ownedBy wireID: UInt64) -> KartInfo? {
        karts.first { $0.ownerWireID == wireID && wireID != 0 }
    }

    public func encoded() throws -> [UInt8] {
        guard karts.count <= Int(UInt16.max), leaderboard.count <= Int(UInt16.max) else {
            throw CodecError.invalidValue
        }
        var w = ByteWriter()
        w.write(UInt16(karts.count))
        for kart in karts {
            try w.write(kart.id)
            w.write(kart.ownerWireID)
            w.write(kart.x)
            w.write(kart.y)
            w.write(kart.heading)
        }
        w.write(UInt16(leaderboard.count))
        for record in leaderboard {
            try w.write(record.playerID)
            try w.write(record.displayName)
            w.write(record.timeMs)
        }
        return w.bytes
    }

    public init(decoding bytes: [UInt8]) throws {
        var r = ByteReader(bytes)
        var karts: [KartInfo] = []
        for _ in 0..<Int(try r.readUInt16()) {
            karts.append(
                KartInfo(
                    id: try r.readString(), ownerWireID: try r.readUInt64(),
                    x: try r.readFloat(), y: try r.readFloat(), heading: try r.readFloat()))
        }
        var leaderboard: [LapRecord] = []
        for _ in 0..<Int(try r.readUInt16()) {
            leaderboard.append(
                LapRecord(
                    playerID: try r.readString(), displayName: try r.readString(),
                    timeMs: try r.readUInt32()))
        }
        self.init(karts: karts, leaderboard: leaderboard)
    }
}

/// Joiner → host race actions. The host validates every one (ADR 0006).
public enum RaceCommand: Equatable, Sendable {
    case mount(kartID: String)
    case dismount
    case horn

    private enum Kind: UInt8 { case mount = 1, dismount = 2, horn = 3 }

    public func encoded() throws -> [UInt8] {
        var w = ByteWriter()
        switch self {
        case .mount(let kartID):
            w.write(Kind.mount.rawValue)
            try w.write(kartID)
        case .dismount:
            w.write(Kind.dismount.rawValue)
        case .horn:
            w.write(Kind.horn.rawValue)
        }
        return w.bytes
    }

    public init(decoding bytes: [UInt8]) throws {
        var r = ByteReader(bytes)
        guard let kind = Kind(rawValue: try r.readUInt8()) else { throw CodecError.invalidValue }
        switch kind {
        case .mount: self = .mount(kartID: try r.readString())
        case .dismount: self = .dismount
        case .horn: self = .horn
        }
    }
}

/// Bits of `PlayerSnapshot.mode`.
public enum PlayerMode {
    public static let kart: UInt8 = 1 << 0
    public static let drifting: UInt8 = 1 << 1
}

/// Bits of `InputFrame.flags`.
public enum InputFlags {
    public static let drift: UInt8 = 1 << 0
}

/// Reach for mounting: how close you must stand to a parked kart.
public enum RaceRules {
    public static let mountReachTiles: Double = 2.0

    /// Ordered checkpoints (cp-0 first) from a map, ready for `LapTracker`.
    public static func checkpoints(in map: WorldMap) -> [WorldMap.Zone] {
        map.zones.filter { $0.type == "checkpoint" }.sorted { $0.name < $1.name }
    }

    public static func kartPads(in map: WorldMap) -> [WorldMap.Zone] {
        map.zones.filter { $0.type == "kart" }.sorted { $0.name < $1.name }
    }
}
