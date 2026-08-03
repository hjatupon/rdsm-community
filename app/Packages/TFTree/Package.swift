// swift-tools-version: 6.0
import PackageDescription

// M13 TFTree — Layer 3 (Domain). Maintains a TF2-compatible transform tree with
// temporal history, BFS path-finding, and SLERP-interpolated lookups.
// Contract C4: lookup never throws — returns nil on failure.
// Uses Double precision throughout to match tf2 reference accuracy.
let package = Package(
    name: "TFTree",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "TFTree", targets: ["TFTree"]),
    ],
    dependencies: [
        .package(path: "../Logging"),
    ],
    targets: [
        .target(
            name: "TFTree",
            dependencies: ["Logging"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .unsafeFlags(["-strict-concurrency=complete"]),
            ]
        ),
        .testTarget(
            name: "TFTreeTests",
            dependencies: ["TFTree"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
    ]
)
