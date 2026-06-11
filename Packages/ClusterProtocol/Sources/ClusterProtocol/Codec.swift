import Foundation

/// Compact little-endian binary codec used for every wire message.
/// Hand-rolled on purpose: payloads are tiny and hot (15 Hz snapshots, voice
/// framing), both ends are Swift, and the format stays inspectable.

public enum CodecError: Error, Equatable {
    /// Tried to read past the end of the buffer.
    case underflow
    /// A length prefix or enum raw value was outside its valid range.
    case invalidValue
    /// A string field did not contain valid UTF-8.
    case invalidUTF8
}

public struct ByteWriter: Sendable {
    public private(set) var bytes: [UInt8] = []

    public init() {}

    public mutating func write(_ value: UInt8) {
        bytes.append(value)
    }

    public mutating func write(_ value: UInt16) {
        withUnsafeBytes(of: value.littleEndian) { bytes.append(contentsOf: $0) }
    }

    public mutating func write(_ value: UInt32) {
        withUnsafeBytes(of: value.littleEndian) { bytes.append(contentsOf: $0) }
    }

    public mutating func write(_ value: UInt64) {
        withUnsafeBytes(of: value.littleEndian) { bytes.append(contentsOf: $0) }
    }

    public mutating func write(_ value: Double) {
        write(value.bitPattern)
    }

    public mutating func write(_ value: Bool) {
        write(UInt8(value ? 1 : 0))
    }

    public mutating func write(_ value: Vec2) {
        write(value.x)
        write(value.y)
    }

    /// UTF-8 with a UInt16 byte-length prefix. Display names, codes — never bulk data.
    public mutating func write(_ value: String) throws {
        let utf8 = Array(value.utf8)
        guard utf8.count <= Int(UInt16.max) else { throw CodecError.invalidValue }
        write(UInt16(utf8.count))
        bytes.append(contentsOf: utf8)
    }

    /// Raw bytes with a UInt16 length prefix (keys, signatures, fingerprints).
    public mutating func write(_ value: Data) throws {
        guard value.count <= Int(UInt16.max) else { throw CodecError.invalidValue }
        write(UInt16(value.count))
        bytes.append(contentsOf: value)
    }
}

public struct ByteReader: Sendable {
    private let bytes: [UInt8]
    public private(set) var offset: Int = 0

    public init(_ bytes: [UInt8]) {
        self.bytes = bytes
    }

    public init(_ data: Data) {
        self.bytes = [UInt8](data)
    }

    public var remaining: Int {
        bytes.count - offset
    }

    private mutating func take(_ count: Int) throws -> ArraySlice<UInt8> {
        guard remaining >= count else { throw CodecError.underflow }
        defer { offset += count }
        return bytes[offset..<offset + count]
    }

    public mutating func readUInt8() throws -> UInt8 {
        try take(1).first!
    }

    public mutating func readUInt16() throws -> UInt16 {
        var value: UInt16 = 0
        for (i, byte) in try take(2).enumerated() {
            value |= UInt16(byte) << (8 * i)
        }
        return value
    }

    public mutating func readUInt32() throws -> UInt32 {
        var value: UInt32 = 0
        for (i, byte) in try take(4).enumerated() {
            value |= UInt32(byte) << (8 * i)
        }
        return value
    }

    public mutating func readUInt64() throws -> UInt64 {
        var value: UInt64 = 0
        for (i, byte) in try take(8).enumerated() {
            value |= UInt64(byte) << (8 * i)
        }
        return value
    }

    public mutating func readDouble() throws -> Double {
        Double(bitPattern: try readUInt64())
    }

    public mutating func readBool() throws -> Bool {
        switch try readUInt8() {
        case 0: return false
        case 1: return true
        default: throw CodecError.invalidValue
        }
    }

    public mutating func readVec2() throws -> Vec2 {
        Vec2(x: try readDouble(), y: try readDouble())
    }

    public mutating func readString() throws -> String {
        let count = Int(try readUInt16())
        guard let string = String(bytes: try take(count), encoding: .utf8) else {
            throw CodecError.invalidUTF8
        }
        return string
    }

    public mutating func readData() throws -> Data {
        let count = Int(try readUInt16())
        return Data(try take(count))
    }
}
