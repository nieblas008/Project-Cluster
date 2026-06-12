// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClusterNet",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),  // the future join-only mobile client reuses this package
    ],
    products: [
        .library(name: "ClusterNet", targets: ["ClusterNet"]),
        .executable(name: "cluster-smoke", targets: ["cluster-smoke"]),
    ],
    dependencies: [
        .package(path: "../ClusterProtocol"),
        .package(path: "../ClusterVoice"),
    ],
    targets: [
        .target(name: "ClusterNet", dependencies: ["ClusterProtocol"]),
        // End-to-end harness: hosts and joins through a real relay, used by CI
        // and scripts/itest-phase1.sh. Not part of the app. ClusterVoice is
        // here for synthetic voice frames — the library target stays audio-free.
        .executableTarget(name: "cluster-smoke", dependencies: ["ClusterNet", "ClusterVoice"]),
        .testTarget(name: "ClusterNetTests", dependencies: ["ClusterNet"]),
    ]
)
