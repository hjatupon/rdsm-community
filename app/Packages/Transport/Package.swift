// swift-tools-version: 6.0
import PackageDescription

// Min macOS: .v15 (Sequoia) fallback floor per 08-tech-stack §18.
// Primary target macOS 26 Tahoe; gate Metal 4 / Liquid Glass behind #available(macOS 26, *).
//
// M3 Transport — Layer 0. rosbridge_suite WebSocket client + deterministic mock.
// Depends on Logging (M1) and Serialization (M2); no third-party deps (URLSession WS).
let package = Package(
    name: "Transport",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "Transport", targets: ["Transport"]),
        .executable(name: "TransportDemo", targets: ["TransportDemo"]),
    ],
    dependencies: [
        .package(path: "../Logging"),
        .package(path: "../Serialization"),
    ],
    targets: [
        .target(
            name: "Transport",
            dependencies: ["Logging", "Serialization"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .unsafeFlags(["-strict-concurrency=complete"]),
            ]
        ),
        .testTarget(
            name: "TransportTests",
            dependencies: ["Transport"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .executableTarget(
            name: "TransportDemo",
            dependencies: ["Transport"],
            path: "Demo/TransportDemo"
        ),
    ]
)
