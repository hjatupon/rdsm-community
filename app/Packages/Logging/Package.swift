// swift-tools-version: 6.0
import PackageDescription

// Min macOS: .v15 (Sequoia) is the fallback floor per 08-tech-stack §18.
// Primary target is macOS 26 Tahoe; gate Liquid Glass / Metal 4 behind #available(macOS 26, *).
let package = Package(
    name: "Logging",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "Logging", targets: ["Logging"]),
        .executable(name: "LoggingDemo", targets: ["LoggingDemo"]),
    ],
    targets: [
        .target(
            name: "Logging",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .unsafeFlags(["-strict-concurrency=complete"]),
            ]
        ),
        .testTarget(
            name: "LoggingTests",
            dependencies: ["Logging"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .executableTarget(
            name: "LoggingDemo",
            dependencies: ["Logging"],
            path: "Demo/LoggingDemo"
        ),
    ]
)
