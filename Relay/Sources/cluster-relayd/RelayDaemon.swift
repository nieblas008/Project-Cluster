import ArgumentParser
import Logging
import NIOCore
import NIOPosix
import NIOSSL
import RelayCore

@main
struct RelayDaemon: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cluster-relayd",
        abstract: "Project Cluster rendezvous + splice relay (stateless)."
    )

    @Option(help: "TCP port for the TLS control plane.")
    var controlPort: Int = 7600

    @Option(help: "UDP port for the echo/data plane.")
    var udpPort: Int = 7601

    @Option(help: "Path to the TLS certificate (PEM). See docs/runbooks/relay.md.")
    var tlsCert: String

    @Option(help: "Path to the TLS private key (PEM).")
    var tlsKey: String

    mutating func run() async throws {
        let logger = Logger(label: "cluster-relayd")
        let registry = SessionRegistry()
        let flows = FlowTable()

        let certificates = try NIOSSLCertificate.fromPEMFile(tlsCert)
        let tlsConfiguration = TLSConfiguration.makeServerConfiguration(
            certificateChain: certificates.map { .certificate($0) },
            privateKey: .file(tlsKey)
        )
        let sslContext = try NIOSSLContext(configuration: tlsConfiguration)

        let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)

        let control = try await ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                channel.eventLoop.makeCompletedFuture {
                    try channel.pipeline.syncOperations.addHandler(
                        NIOSSLServerHandler(context: sslContext))
                    try channel.pipeline.syncOperations.addHandler(
                        ControlHandler(registry: registry, flows: flows, logger: logger))
                }
            }
            .bind(host: "0.0.0.0", port: controlPort)
            .get()

        let udp = try await DatagramBootstrap(group: group)
            .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .channelInitializer { channel in
                channel.eventLoop.makeCompletedFuture {
                    try channel.pipeline.syncOperations.addHandler(
                        UDPFlowHandler(flows: flows, logger: logger))
                }
            }
            .bind(host: "0.0.0.0", port: udpPort)
            .get()

        logger.info(
            "cluster-relayd \(RelayInfo.version) up — control :\(controlPort)/tcp (TLS), data :\(udpPort)/udp"
        )

        try await control.closeFuture.get()
        try await udp.closeFuture.get()
        try await group.shutdownGracefully()
    }
}
