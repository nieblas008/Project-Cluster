// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClusterVoice",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(name: "ClusterVoice", targets: ["ClusterVoice"])
    ],
    dependencies: [
        .package(path: "../ClusterProtocol")
    ],
    targets: [
        // Phase 3 fills this in: voice-processed capture, Opus, jitter buffer,
        // per-speaker playback. Phase 0 pins the format every layer agrees on.
        .target(name: "ClusterVoice", dependencies: ["ClusterProtocol"]),
        .testTarget(name: "ClusterVoiceTests", dependencies: ["ClusterVoice"]),
    ]
)
