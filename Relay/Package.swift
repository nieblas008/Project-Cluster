// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Relay",
    platforms: [
        .macOS(.v14)  // local dev; production target is Linux (Docker)
    ],
    products: [
        .executable(name: "cluster-relayd", targets: ["cluster-relayd"])
    ],
    dependencies: [
        .package(path: "../Packages/ClusterProtocol"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.65.0"),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.26.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
    ],
    targets: [
        // Logic lives here so it's unit-testable; the executable stays thin.
        .target(
            name: "RelayCore",
            dependencies: [
                "ClusterProtocol",
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOConcurrencyHelpers", package: "swift-nio"),
                .product(name: "Logging", package: "swift-log"),
            ]
        ),
        .executableTarget(
            name: "cluster-relayd",
            dependencies: [
                "RelayCore",
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOSSL", package: "swift-nio-ssl"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "RelayCoreTests",
            dependencies: [
                "RelayCore",
                .product(name: "NIOEmbedded", package: "swift-nio"),
            ]
        ),
    ]
)
