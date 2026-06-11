import Foundation

/// First bytes of every conversation: each side announces its wire version and
/// app version so mismatches fail with a clear message instead of garbled reads.
/// The full message catalog (join, snapshots, voice frames…) arrives with its
/// feature's phase; everything follows this struct's encode/decode shape.
public struct ProtocolHello: Equatable, Sendable {
    public var wireVersion: UInt16
    public var appVersion: String

    public init(wireVersion: UInt16 = ProtocolInfo.wireVersion, appVersion: String) {
        self.wireVersion = wireVersion
        self.appVersion = appVersion
    }

    public func encoded() throws -> [UInt8] {
        var writer = ByteWriter()
        writer.write(wireVersion)
        try writer.write(appVersion)
        return writer.bytes
    }

    public init(decoding bytes: [UInt8]) throws {
        var reader = ByteReader(bytes)
        self.wireVersion = try reader.readUInt16()
        self.appVersion = try reader.readString()
    }
}
