// swift-tools-version: 6.0
import PackageDescription

/// Min macOS: .v15 (Sequoia) fallback floor per 08-tech-stack §18.
/// Primary target macOS 26 Tahoe; the Metal 4 PBR fast path is gated behind
/// #available(macOS 26, *) and signed off on Apple Silicon (PENDING-AS).
///
/// 0.2.0: RobotModel/Link/Joint/Transform extracted to RobotModelCore (Layer 1) so
/// URDFParser (M9, Layer 2) can depend on the value types without importing Metal.
/// @_exported import in the re-export shim preserves source compatibility for callers
/// that only import RobotModelRenderer.
let package = Package(
    name: "RobotModelRenderer",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "RobotModelRenderer", targets: ["RobotModelRenderer"]),
        .executable(name: "RobotModelDemo", targets: ["RobotModelDemo"]),
    ],
    dependencies: [
        .package(path: "../MetalCore"),
        .package(path: "../Logging"),
        .package(path: "../RobotModelCore"),
        .package(path: "../MeshLoader"),
        .package(path: "../PointCloudRenderer"),
    ],
    targets: [
        .target(
            name: "RobotModelRenderer",
            dependencies: ["MetalCore", "Logging", "RobotModelCore", "MeshLoader", "PointCloudRenderer"],
            resources: [.process("Shaders")],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .unsafeFlags(["-strict-concurrency=complete"]),
            ]),
        .testTarget(
            name: "RobotModelRendererTests",
            dependencies: ["RobotModelRenderer", "MetalCore", "Logging"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]),
        .executableTarget(
            name: "RobotModelDemo",
            dependencies: ["RobotModelRenderer", "MetalCore"],
            path: "Demo/RobotModelDemo"),
    ])
