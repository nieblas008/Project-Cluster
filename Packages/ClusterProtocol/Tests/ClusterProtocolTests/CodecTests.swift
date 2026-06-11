import Foundation
import Testing

@testable import ClusterProtocol

@Suite struct CodecTests {
    @Test func roundTripsScalars() throws {
        var writer = ByteWriter()
        writer.write(UInt8(7))
        writer.write(UInt16(513))
        writer.write(UInt32(70_000))
        writer.write(UInt64.max - 1)
        writer.write(-12.5)
        writer.write(true)
        writer.write(false)

        var reader = ByteReader(writer.bytes)
        #expect(try reader.readUInt8() == 7)
        #expect(try reader.readUInt16() == 513)
        #expect(try reader.readUInt32() == 70_000)
        #expect(try reader.readUInt64() == UInt64.max - 1)
        #expect(try reader.readDouble() == -12.5)
        #expect(try reader.readBool() == true)
        #expect(try reader.readBool() == false)
        #expect(reader.remaining == 0)
    }

    @Test func roundTripsStringsVectorsAndData() throws {
        var writer = ByteWriter()
        try writer.write("Río & 🏎️")
        writer.write(Vec2(x: 3.25, y: -8))
        try writer.write(Data([0xDE, 0xAD, 0xBE, 0xEF]))

        var reader = ByteReader(writer.bytes)
        #expect(try reader.readString() == "Río & 🏎️")
        #expect(try reader.readVec2() == Vec2(x: 3.25, y: -8))
        #expect(try reader.readData() == Data([0xDE, 0xAD, 0xBE, 0xEF]))
    }

    @Test func littleEndianLayoutIsStable() {
        var writer = ByteWriter()
        writer.write(UInt16(0x0102))
        #expect(writer.bytes == [0x02, 0x01])
    }

    @Test func readingPastEndThrowsUnderflow() {
        var reader = ByteReader([0x01])
        #expect(throws: CodecError.underflow) {
            _ = try reader.readUInt16()
        }
    }

    @Test func malformedBoolThrowsInvalidValue() {
        var reader = ByteReader([0x02])
        #expect(throws: CodecError.invalidValue) {
            _ = try reader.readBool()
        }
    }

    @Test func helloRoundTrips() throws {
        let hello = ProtocolHello(appVersion: "0.1.0")
        let decoded = try ProtocolHello(decoding: try hello.encoded())
        #expect(decoded == hello)
        #expect(decoded.wireVersion == ProtocolInfo.wireVersion)
    }
}
