import ClusterProtocol
import Logging
import NIOCore
import NIOEmbedded
import Testing

@testable import RelayCore

@Suite struct FlowTableTests {
    func address(_ port: Int) throws -> SocketAddress {
        try SocketAddress(ipAddress: "10.0.0.\(port % 250 + 1)", port: port)
    }

    @Test func bindsBothSidesAndRoutesBetweenThem() throws {
        let table = FlowTable()
        let flow = table.createFlow()
        let hostAddr = try address(1001)
        let joinerAddr = try address(2002)

        #expect(table.bind(flowID: flow.flowID, token: flow.hostToken, address: hostAddr) == .host)
        #expect(
            table.bind(flowID: flow.flowID, token: flow.joinerToken, address: joinerAddr) == .joiner)

        #expect(table.destination(flowID: flow.flowID, from: hostAddr) == joinerAddr)
        #expect(table.destination(flowID: flow.flowID, from: joinerAddr) == hostAddr)
        // Strangers don't route.
        #expect(table.destination(flowID: flow.flowID, from: try address(3003)) == nil)
    }

    @Test func wrongTokenDoesNotBind() throws {
        let table = FlowTable()
        let flow = table.createFlow()
        #expect(table.bind(flowID: flow.flowID, token: 12345, address: try address(1)) == nil)
        #expect(table.bind(flowID: 999, token: flow.hostToken, address: try address(1)) == nil)
    }

    @Test func rebindUpdatesAddress() throws {
        let table = FlowTable()
        let flow = table.createFlow()
        _ = table.bind(flowID: flow.flowID, token: flow.hostToken, address: try address(1))
        _ = table.bind(flowID: flow.flowID, token: flow.joinerToken, address: try address(2))
        // NAT rebinding: host shows up from a new port.
        let newHostAddr = try address(7)
        #expect(table.bind(flowID: flow.flowID, token: flow.hostToken, address: newHostAddr) == .host)
        #expect(table.destination(flowID: flow.flowID, from: try address(2)) == newHostAddr)
    }

    @Test func sweepDropsIdleFlows() {
        let table = FlowTable()
        _ = table.createFlow()
        #expect(table.flowCount == 1)
        #expect(table.sweep(now: .now() + .seconds(300)) == 1)
        #expect(table.flowCount == 0)
    }
}

@Suite struct UDPFlowHandlerTests {
    func makeChannel(flows: FlowTable) throws -> EmbeddedChannel {
        let channel = EmbeddedChannel()
        try channel.pipeline.syncOperations.addHandler(
            UDPFlowHandler(flows: flows, logger: Logger(label: "test")))
        return channel
    }

    func envelope(
        _ bytes: [UInt8], from address: SocketAddress, on channel: EmbeddedChannel
    ) -> AddressedEnvelope<ByteBuffer> {
        var buffer = channel.allocator.buffer(capacity: bytes.count)
        buffer.writeBytes(bytes)
        return AddressedEnvelope(remoteAddress: address, data: buffer)
    }

    @Test func bindIsAckedDataIsForwardedProbeIsEchoed() throws {
        let flows = FlowTable()
        let flow = flows.createFlow()
        let channel = try makeChannel(flows: flows)
        let hostAddr = try SocketAddress(ipAddress: "10.1.1.1", port: 5000)
        let joinerAddr = try SocketAddress(ipAddress: "10.2.2.2", port: 6000)

        // Host bind → ack echoed back to host.
        try channel.writeInbound(
            envelope(
                DatagramWire.encodeBind(flowID: flow.flowID, token: flow.hostToken),
                from: hostAddr, on: channel))
        let bindAck = try channel.readOutbound(as: AddressedEnvelope<ByteBuffer>.self)
        #expect(bindAck?.remoteAddress == hostAddr)

        // Joiner bind.
        try channel.writeInbound(
            envelope(
                DatagramWire.encodeBind(flowID: flow.flowID, token: flow.joinerToken),
                from: joinerAddr, on: channel))
        _ = try channel.readOutbound(as: AddressedEnvelope<ByteBuffer>.self)

        // Data from joiner lands at host, bytes untouched.
        let packet = DatagramWire.encodeData(flowID: flow.flowID, seq: 1, ciphertext: [9, 8, 7])
        try channel.writeInbound(envelope(packet, from: joinerAddr, on: channel))
        let forwarded = try channel.readOutbound(as: AddressedEnvelope<ByteBuffer>.self)
        #expect(forwarded?.remoteAddress == hostAddr)
        #expect(
            forwarded.map { Array($0.data.readableBytesView) } == packet)

        // Unknown small packet (the Doctor's probe) still echoes.
        let probeAddr = try SocketAddress(ipAddress: "10.3.3.3", port: 7000)
        try channel.writeInbound(envelope([1, 2, 3, 4, 5, 6, 7, 8], from: probeAddr, on: channel))
        let echoed = try channel.readOutbound(as: AddressedEnvelope<ByteBuffer>.self)
        #expect(echoed?.remoteAddress == probeAddr)

        // Bad bind token: silence.
        try channel.writeInbound(
            envelope(
                DatagramWire.encodeBind(flowID: flow.flowID, token: 42),
                from: probeAddr, on: channel))
        #expect(try channel.readOutbound(as: AddressedEnvelope<ByteBuffer>.self) == nil)
    }
}
