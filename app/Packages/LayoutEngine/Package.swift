// swift-tools-version: 6.0
import PackageDescription

// M15 LayoutEngine — Layer 3 (Domain). Named workspace serialisation with version
// migration. iCloud sync stub (changes stream, CloudKit wired in Phase 2).
let package = Package(
    name: "LayoutEngine",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "LayoutEngine", targets: ["LayoutEngine"]),
        .executable(name: "LayoutDemo", targets: ["LayoutDemo"]),
    ],
    dependencies: [
        .package(path: "../Logging"),
    ],
    targets: [
        .target(
            name: "LayoutEngine",
            dependencies: ["Logging"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .unsafeFlags(["-strict-concurrency=complete"]),
            ]
        ),
        .executableTarget(
            name: "LayoutDemo",
            dependencies: ["LayoutEngine"],
            path: "Demo/LayoutDemo",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "LayoutEngineTests",
            dependencies: ["LayoutEngine"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
