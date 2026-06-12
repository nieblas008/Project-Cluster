import Foundation

/// Compact per-player wire identity: the first 8 bytes of the identity public
/// key. Full hex IDs (64 chars) would multiply snapshot size by ~4 for zero
/// benefit at team scale; the roster (tunnel) carries the full mapping.
public enum PlayerWireID {
    public static func prefix(fromHexID hexID: String) -> UInt64 {
        var value: UInt64 = 0
        for char in hexID.prefix(16) {
            guard let digit = char.hexDigitValue else { break }
            value = (value << 4) | UInt64(digit)
        }
        return value
    }
}

public struct PlayerSnapshot: Equatable, Sendable {
    public var id: UInt64
    public var x: Float
    public var y: Float
    public var facing: Facing
    public var isMoving: Bool

    public init(id: UInt64, x: Float, y: Float, facing: Facing, isMoving: Bool) {
        self.id = id
        self.x = x
        self.y = y
        self.facing = facing
        self.isMoving = isMoving
    }

    public var position: Vec2 { Vec2(x: Double(x), y: Double(y)) }
}

/// Host → everyone, 15 times a second, latest-wins.
public struct WorldSnapshot: Equatable, Sendable {
    public var tick: UInt32
    public var players: [PlayerSnapshot]

    public init(tick: UInt32, players: [PlayerSnapshot]) {
        self.tick = tick
        self.players = players
    }
}

/// Client → host: intent + client-authoritative position (validated, PLAN §7).
public struct InputFrame: Equatable, Sendable {
    public var seq: UInt32
    public var input: MoveInput
    public var x: Float
    public var y: Float

    public init(seq: UInt32, input: MoveInput, x: Float, y: Float) {
        self.seq = seq
        self.input = input
        self.x = x
        self.y = y
    }
}

/// Everything that rides the world channel — sealed datagrams when UDP works,
/// `worldFrame` tunnel messages when it doesn't (ADR 0002). One codec, two roads.
public enum WorldPayload: Equatable, Sendable {
    case input(InputFrame)
    case snapshot(WorldSnapshot)
    /// One 20 ms Opus frame. Joiner→host: speakerID is overwritten by the host
    /// with the pair's verified identity (no voice spoofing); host→joiner:
    /// speakerID tells the receiver whose jitter buffer this feeds.
    case voice(speakerID: UInt64, seq: UInt32, opus: Data)

    private enum Kind: UInt8 {
        case input = 1
        case snapshot = 2
        case voice = 3
    }

    public func encoded() throws -> [UInt8] {
        var w = ByteWriter()
        switch self {
        case .input(let frame):
            w.write(Kind.input.rawValue)
            w.write(frame.seq)
            w.write(frame.input.dirX)
            w.write(frame.input.dirY)
            w.write(frame.x)
            w.write(frame.y)
        case .snapshot(let snapshot):
            w.write(Kind.snapshot.rawValue)
            w.write(snapshot.tick)
            guard snapshot.players.count <= 255 else { throw CodecError.invalidValue }
            w.write(UInt8(snapshot.players.count))
            for player in snapshot.players {
                w.write(player.id)
                w.write(player.x)
                w.write(player.y)
                w.write(player.facing.rawValue)
                w.write(player.isMoving)
            }
        case .voice(let speakerID, let seq, let opus):
            w.write(Kind.voice.rawValue)
            w.write(speakerID)
            w.write(seq)
            try w.write(opus)
        }
        return w.bytes
    }

    public init(decoding bytes: [UInt8]) throws {
        var r = ByteReader(bytes)
        guard let kind = Kind(rawValue: try r.readUInt8()) else { throw CodecError.invalidValue }
        switch kind {
        case .input:
            self = .input(
                InputFrame(
                    seq: try r.readUInt32(),
                    input: MoveInput(dirX: try r.readInt8(), dirY: try r.readInt8()),
                    x: try r.readFloat(),
                    y: try r.readFloat()
                ))
        case .snapshot:
            let tick = try r.readUInt32()
            let count = Int(try r.readUInt8())
            var players: [PlayerSnapshot] = []
            players.reserveCapacity(count)
            for _ in 0..<count {
                let id = try r.readUInt64()
                let x = try r.readFloat()
                let y = try r.readFloat()
                guard let facing = Facing(rawValue: try r.readUInt8()) else {
                    throw CodecError.invalidValue
                }
                players.append(
                    PlayerSnapshot(
                        id: id, x: x, y: y, facing: facing, isMoving: try r.readBool()))
            }
            self = .snapshot(WorldSnapshot(tick: tick, players: players))
        case .voice:
            self = .voice(
                speakerID: try r.readUInt64(), seq: try r.readUInt32(), opus: try r.readData())
        }
    }
}

/// Remote avatars render ~120 ms in the past, lerping between buffered
/// snapshots (PLAN §7) — the difference between "Gather" and "teleporting robots".
public struct RemotePlayerInterpolator: Sendable {
    public static let renderDelay: Double = 0.12

    private var samples: [(time: Double, snapshot: PlayerSnapshot)] = []

    public init() {}

    public mutating func record(_ snapshot: PlayerSnapshot, at time: Double) {
        samples.append((time, snapshot))
        if samples.count > 12 {
            samples.removeFirst(samples.count - 12)
        }
    }

    /// Sample at (now - renderDelay). Clamps at the ends — never extrapolates.
    public func sample(at time: Double) -> PlayerSnapshot? {
        guard let first = samples.first, let last = samples.last else { return nil }
        if time <= first.time { return first.snapshot }
        if time >= last.time { return last.snapshot }
        for index in 1..<samples.count {
            let (t0, s0) = samples[index - 1]
            let (t1, s1) = samples[index]
            if time <= t1 {
                let t = (time - t0) / max(t1 - t0, 0.0001)
                var blended = s1
                blended.x = Float(lerp(Double(s0.x), Double(s1.x), t: t))
                blended.y = Float(lerp(Double(s0.y), Double(s1.y), t: t))
                blended.facing = t < 0.5 ? s0.facing : s1.facing
                blended.isMoving = s1.isMoving || s0.isMoving
                return blended
            }
        }
        return last.snapshot
    }
}
