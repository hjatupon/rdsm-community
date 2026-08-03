// swift-tools-version: 6.0
import PackageDescription

/// Min macOS: .v15 (Sequoia) fallback floor per 08-tech-stack §18.
/// Primary target macOS 26 Tahoe; mesh-shader / compute-cull fast paths are gated
/// behind #available(macOS 26, *) and signed off on Apple Silicon (PENDING-AS).
let package = Package(
    name: "PointCloudRenderer",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "PointCloudRenderer", targets: ["PointCloudRenderer"]),
        .executable(name: "PointCloudDemo", targets: ["PointCloudDemo"]),
    ],
    dependencies: [
        .package(path: "../MetalCore"),
        .package(path: "../Logging"),
    ],
    targets: [
        .target(
            name: "PointCloudRenderer",
            dependencies: ["MetalCore", "Logging"],
            resources: [.process("Shaders")],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .unsafeFlags(["-strict-concurrency=complete"]),
            ]),
        .testTarget(
            name: "PointCloudRendererTests",
            dependencies: ["PointCloudRenderer", "MetalCore"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]),
        .executableTarget(
            name: "PointCloudDemo",
            dependencies: ["PointCloudRenderer", "MetalCore"],
            path: "Demo/PointCloudDemo"),
    ])
