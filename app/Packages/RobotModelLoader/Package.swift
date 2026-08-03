// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RobotModelLoader",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "RobotModelLoader", targets: ["RobotModelLoader"]),
    ],
    dependencies: [
        .package(path: "../Logging"),
        .package(path: "../MetalCore"),
        .package(path: "../URDFParser"),
        .package(path: "../RobotModelCore"),
        .package(path: "../MeshLoader"),
    ],
    targets: [
        .target(
            name: "RobotModelLoader",
            dependencies: ["Logging", "MetalCore", "URDFParser", "RobotModelCore", "MeshLoader"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .unsafeFlags(["-strict-concurrency=complete"]),
            ]
        ),
    ]
)
