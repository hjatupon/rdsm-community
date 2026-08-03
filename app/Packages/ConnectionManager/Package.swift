// swift-tools-version: 6.0
import PackageDescription

// M14 ConnectionManager — Layer 3 (Domain). Manages named connection profiles,
// deduplication (one handle per URL), lifecycle broadcasting via AsyncStream,
// and reconnect-all. Delegates wire protocol to Transport conformers.
let package = Package(
    name: "ConnectionManager",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "ConnectionManager", targets: ["ConnectionManager"]),
    ],
    dependencies: [
        .package(path: "../Logging"),
        .package(path: "../Transport"),
    ],
    targets: [
        .target(
            name: "ConnectionManager",
            dependencies: ["Logging", "Transport"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .unsafeFlags(["-strict-concurrency=complete"]),
            ]
        ),
        .testTarget(
            name: "ConnectionManagerTests",
            dependencies: ["ConnectionManager", "Transport"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
    ]
)
