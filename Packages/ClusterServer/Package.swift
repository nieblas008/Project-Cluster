// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClusterServer",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "ClusterServer", targets: ["ClusterServer"])
    ],
    dependencies: [
        .package(path: "../ClusterProtocol"),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    ],
    targets: [
        .target(
            name: "ClusterServer",
            dependencies: [
                "ClusterProtocol",
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        .testTarget(name: "ClusterServerTests", dependencies: ["ClusterServer"]),
    ]
)
