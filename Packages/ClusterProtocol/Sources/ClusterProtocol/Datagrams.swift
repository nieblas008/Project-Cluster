/// Raw datagram layouts for the relay's UDP data plane (ADR 0002). Pure byte
/// shuffling — the crypto lives in ClusterNet, the routing in RelayCore, and
/// this file is the single source of truth for what's where.
public enum DatagramWire {
    /// "CBND" — flowIDs are small sequential integers, so a data packet's
    /// little-endian flowID can never collide with this magic (≈1.1 billion).
    public static let bindMagic: [UInt8] = Array("CBND".utf8)

    /// bind = magic(4) ‖ flowID(4 LE) ‖ token(8 LE)
    public static func encodeBind(flowID: UInt32, token: UInt64) -> [UInt8] {
        var w = ByteWriter()
        w.writeRaw(bindMagic)
        w.write(flowID)
        w.write(token)
        return w.bytes
    }

    public static func decodeBind(_ bytes: [UInt8]) -> (flowID: UInt32, token: UInt64)? {
        guard bytes.count == 16, Array(bytes[0..<4]) == bindMagic else { return nil }
        var r = ByteReader(Array(bytes[4...]))
        guard let flowID = try? r.readUInt32(), let token = try? r.readUInt64() else { return nil }
        return (flowID, token)
    }

    /// data = flowID(4 LE) ‖ seq(8 LE) ‖ ciphertext
    public static func encodeData(flowID: UInt32, seq: UInt64, ciphertext: [UInt8]) -> [UInt8] {
        var w = ByteWriter()
        w.write(flowID)
        w.write(seq)
        w.writeRaw(ciphertext)
        return w.bytes
    }

    public static func decodeData(_ bytes: [UInt8]) -> (flowID: UInt32, seq: UInt64, ciphertext: [UInt8])? {
        guard bytes.count > 12 else { return nil }
        var r = ByteReader(bytes)
        guard let flowID = try? r.readUInt32(), let seq = try? r.readUInt64() else { return nil }
        return (flowID, seq, Array(bytes[12...]))
    }

    /// The relay routes on this without touching the rest.
    public static func peekFlowID(_ bytes: [UInt8]) -> UInt32? {
        guard bytes.count > 12, Array(bytes[0..<4]) != bindMagic else { return nil }
        var r = ByteReader(bytes)
        return try? r.readUInt32()
    }
}
