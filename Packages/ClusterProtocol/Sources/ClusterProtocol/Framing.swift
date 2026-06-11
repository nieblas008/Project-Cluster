import Foundation

/// Every reliable-plane message travels as a frame: UInt16 little-endian
/// payload length, then the payload. Used identically on the control plane and
/// inside the spliced tunnel (where payloads are handshake or sealed bytes).
public enum Frame {
    /// Generous for roster updates, far below any DoS-interesting size.
    public static let maxPayloadLength = 32 * 1024

    public static func encode(_ payload: [UInt8]) throws -> [UInt8] {
        guard payload.count <= maxPayloadLength else { throw CodecError.invalidValue }
        var writer = ByteWriter()
        writer.write(UInt16(payload.count))
        return writer.bytes + payload
    }
}

/// Incremental frame reassembly for stream transports that deliver arbitrary
/// chunks (NWConnection receives, NIO reads). Feed bytes, pop whole frames.
public struct FrameAssembler: Sendable {
    private var buffer: [UInt8] = []

    public init() {}

    public mutating func append(_ bytes: [UInt8]) {
        buffer.append(contentsOf: bytes)
    }

    /// Returns the next complete frame payload, or nil if more bytes are needed.
    /// Throws if a frame announces an oversized payload (protocol violation).
    public mutating func next() throws -> [UInt8]? {
        guard buffer.count >= 2 else { return nil }
        let length = Int(buffer[0]) | (Int(buffer[1]) << 8)
        guard length <= Frame.maxPayloadLength else { throw CodecError.invalidValue }
        guard buffer.count >= 2 + length else { return nil }
        let payload = Array(buffer[2..<2 + length])
        buffer.removeFirst(2 + length)
        return payload
    }

    public var bufferedByteCount: Int { buffer.count }
}
