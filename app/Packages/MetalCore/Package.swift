// swift-tools-version: 6.0
import PackageDescription

// Min macOS: .v15 (Sequoia) fallback floor per 08-tech-stack §18.
// Primary target macOS 26 Tahoe; gate Metal 4 paths behind #available(macOS 26, *).
let package = Package(
    name: "MetalCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "MetalCore", targets: ["MetalCore"]),
        .executable(name: "MetalCoreDemo", targets: ["MetalCoreDemo"]),
    ],
    dependencies: [
        .package(path: "../Logging"),
    ],
    targets: [
        .target(
            name: "MetalCore",
            dependencies: ["Logging"],
            resources: [.process("Shaders")],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .unsafeFlags(["-strict-concurrency=complete"]),
            ]
        ),
        .testTarget(
            name: "MetalCoreTests",
            dependencies: ["MetalCore"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .executableTarget(
            name: "MetalCoreDemo",
            dependencies: ["MetalCore"],
            path: "Demo/MetalCoreDemo"
        ),
    ]
)
