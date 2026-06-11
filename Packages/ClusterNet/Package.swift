// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClusterNet",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),  // the future join-only mobile client reuses this package
    ],
    products: [
        .library(name: "ClusterNet", targets: ["ClusterNet"])
    ],
    dependencies: [
        .package(path: "../ClusterProtocol")
    ],
    targets: [
        .target(name: "ClusterNet", dependencies: ["ClusterProtocol"]),
        .testTarget(name: "ClusterNetTests", dependencies: ["ClusterNet"]),
    ]
)
