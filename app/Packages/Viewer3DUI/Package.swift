// swift-tools-version: 6.0
import PackageDescription

// M20 Viewer3DUI — Layer 4 (Feature UI). Composes PointCloudRenderer, RobotModelRenderer,
// and TFTree into a SwiftUI 3D viewport (NSViewRepresentable → MTKView).
// Milestone F: Viewer3DDemo shows a synthetic LiDAR scan + a 3-link articulated arm.
// Min macOS: .v15 (Sequoia) fallback floor per 08-tech-stack §18.
let package = Package(
    name: "Viewer3DUI",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "Viewer3DUI", targets: ["Viewer3DUI"]),
        .executable(name: "Viewer3DDemo", targets: ["Viewer3DDemo"]),
    ],
    dependencies: [
        .package(path: "../Logging"),
        .package(path: "../Transport"),
        .package(path: "../MessageRegistry"),
        .package(path: "../TopicStore"),
        .package(path: "../TFTree"),
        .package(path: "../MetalCore"),
        .package(path: "../PointCloudRenderer"),
        .package(path: "../RobotModelRenderer"),
        .package(path: "../URDFParser"),
        .package(path: "../MeshLoader"),
        .package(path: "../PublishService"),
    ],
    targets: [
        .target(
            name: "Viewer3DUI",
            dependencies: [
                "Logging",
                "Transport",
                "TopicStore",
                "TFTree",
                "MetalCore",
                "PointCloudRenderer",
                "RobotModelRenderer",
                "URDFParser",
                "MeshLoader",
                "PublishService",
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .unsafeFlags(["-strict-concurrency=complete"]),
            ]
        ),
        .testTarget(
            name: "Viewer3DUITests",
            dependencies: ["Viewer3DUI"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .executableTarget(
            name: "Viewer3DDemo",
            dependencies: [
                "Viewer3DUI",
                "Transport",
                "TopicStore",
                "MessageRegistry",
                "TFTree",
                "MetalCore",
                "PointCloudRenderer",
                "RobotModelRenderer",
            ],
            path: "Demo/Viewer3DDemo"
        ),
    ]
)
