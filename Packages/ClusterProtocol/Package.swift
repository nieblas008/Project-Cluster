// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClusterProtocol",
    products: [
        .library(name: "ClusterProtocol", targets: ["ClusterProtocol"])
    ],
    targets: [
        // Pure Swift + Foundation only. This target must keep compiling on Linux:
        // the relay daemon depends on it.
        .target(name: "ClusterProtocol"),
        .testTarget(name: "ClusterProtocolTests", dependencies: ["ClusterProtocol"]),
    ]
)
