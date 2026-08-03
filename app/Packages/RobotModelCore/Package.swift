// swift-tools-version: 6.0
import PackageDescription

// Min macOS: .v15 (Sequoia) fallback floor per 08-tech-stack §18.
// Primary target macOS 26 Tahoe; gate Liquid Glass / Metal 4 behind #available(macOS 26, *).
//
// RobotModelCore — Layer 1. Pure value types shared by M6 (RobotModelRenderer) and
// M9 (URDFParser). No GPU, no networking, no third-party deps. Extracted from M6 0.1.0
// to break the Layer-2 → Layer-1 dependency inversion (see migration in M6 CHANGELOG 0.2.0).
let package = Package(
    name: "RobotModelCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "RobotModelCore", targets: ["RobotModelCore"]),
    ],
    targets: [
        .target(
            name: "RobotModelCore",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .unsafeFlags(["-strict-concurrency=complete"]),
            ]
        ),
        .testTarget(
            name: "RobotModelCoreTests",
            dependencies: ["RobotModelCore"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
    ]
)
