import ArgumentParser
import Logging
import NIOCore
import NIOPosix
import RelayCore

@main
struct RelayDaemon: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cluster-relayd",
        abstract: "Project Cluster rendezvous + packet relay (stateless)."
    )

    @Option(help: "TCP port for the control plane.")
    var controlPort: Int = 7600

    @Option(help: "UDP port for the data plane.")
    var udpPort: Int = 7601

    mutating func run() async throws {
        let logger = Logger(label: "cluster-relayd")
        let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)

        let control = try await ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                channel.eventLoop.makeCompletedFuture {
                    try channel.pipeline.syncOperations.addHandler(ControlPingHandler())
                }
            }
            .bind(host: "0.0.0.0", port: controlPort)
            .get()

        let udp = try await DatagramBootstrap(group: group)
            .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .channelInitializer { channel in
                channel.eventLoop.makeCompletedFuture {
                    try channel.pipeline.syncOperations.addHandler(UDPEchoHandler())
                }
            }
            .bind(host: "0.0.0.0", port: udpPort)
            .get()

        logger.info("cluster-relayd \(RelayInfo.version) up — control :\(controlPort)/tcp, data :\(udpPort)/udp")

        try await control.closeFuture.get()
        try await udp.closeFuture.get()
        try await group.shutdownGracefully()
    }
}
