// swift-tools-version: 6.0
import PackageDescription

// Min macOS: .v15 (Sequoia) fallback floor per 08-tech-stack §18.
// Primary target macOS 26 Tahoe; gate Liquid Glass / Metal 4 behind #available(macOS 26, *).
//
// M9 URDFParser — Layer 2 (Data & Parsing). Parses URDF XML (Foundation XMLParser) and
// a Xacro subset (include, property, if — NOT macros) into a RobotModel from RobotModelCore.
// Depends on Logging (M1) and RobotModelCore (Layer 1 value types). Does NOT import Metal.
// Contract C7: the parser returns a RobotModel; it never talks to a renderer.
let package = Package(
    name: "URDFParser",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "URDFParser", targets: ["URDFParser"]),
        .executable(name: "URDFDemo", targets: ["URDFDemo"]),
    ],
    dependencies: [
        .package(path: "../Logging"),
        .package(path: "../RobotModelCore"),
    ],
    targets: [
        .target(
            name: "URDFParser",
            dependencies: ["Logging", "RobotModelCore"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .unsafeFlags(["-strict-concurrency=complete"]),
            ]
        ),
        .testTarget(
            name: "URDFParserTests",
            dependencies: ["URDFParser"],
            resources: [.copy("Fixtures")],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .executableTarget(
            name: "URDFDemo",
            dependencies: ["URDFParser"],
            path: "Demo/URDFDemo"
        ),
    ]
)
