// swift-tools-version: 6.0
import PackageDescription

// M19 InspectorUI — Layer 4 (Feature UI). Schema-driven message inspector:
// image viewer for sensor_msgs/Image, inline chart for numeric scalars,
// JSON tree (OutlineGroup) for all other struct types.
// Milestone E: InspectorDemo shows all three render kinds from a synthetic stream.
let package = Package(
    name: "InspectorUI",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "InspectorUI", targets: ["InspectorUI"]),
        .executable(name: "InspectorDemo", targets: ["InspectorDemo"]),
    ],
    dependencies: [
        .package(path: "../Transport"),
        .package(path: "../MessageRegistry"),
        .package(path: "../TopicStore"),
        .package(path: "../ChartingCore"),
        .package(path: "../MetalCore"),
        .package(path: "../LogStore"),
    ],
    targets: [
        .target(
            name: "InspectorUI",
            dependencies: ["Transport", "MessageRegistry", "TopicStore", "ChartingCore", "LogStore"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .unsafeFlags(["-strict-concurrency=complete"]),
            ]
        ),
        .executableTarget(
            name: "InspectorDemo",
            dependencies: ["InspectorUI", "Transport", "MessageRegistry", "TopicStore"],
            path: "Demo/InspectorDemo",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "InspectorUITests",
            dependencies: ["InspectorUI", "Transport"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
