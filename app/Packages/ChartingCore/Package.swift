// swift-tools-version: 6.0
import PackageDescription

// Universal-Mac baseline: builds and runs on Intel macOS 15+ and Apple Silicon.
// No AS-only fast paths in 0.1. Apple Silicon perf characterization deferred to
// a batched QA pass.
let package = Package(
    name: "ChartingCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "ChartingCore", targets: ["ChartingCore"]),
        .executable(name: "ChartingDemo", targets: ["ChartingDemo"]),
    ],
    dependencies: [
        .package(path: "../MetalCore"),
        .package(path: "../Logging"),
    ],
    targets: [
        .target(
            name: "ChartingCore",
            dependencies: ["MetalCore", "Logging"],
            resources: [.process("Shaders")],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .unsafeFlags(["-strict-concurrency=complete"]),
            ]),
        .testTarget(
            name: "ChartingCoreTests",
            dependencies: ["ChartingCore"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]),
        .executableTarget(
            name: "ChartingDemo",
            dependencies: ["ChartingCore", "MetalCore"],
            path: "Demo/ChartingDemo"),
    ])
