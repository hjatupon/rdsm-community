// swift-tools-version: 6.0
import PackageDescription

// Min macOS: .v15 (Sequoia) fallback floor per 08-tech-stack §18.
// Primary target macOS 26 Tahoe; gate Liquid Glass / Metal 4 behind #available(macOS 26, *).
//
// M8 MessageRegistry — Layer 2 (Data & Parsing). Catalogs ~150 ROS2 Jazzy message schemas,
// parses .msg text into typed MessageSchema values, and provides a frozen O(1) lookup.
// DynamicDecoder bridges raw Data payloads (JSON or CDR) into AnyDecodedMessage without
// compile-time schema knowledge.
let package = Package(
    name: "MessageRegistry",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "MessageRegistry", targets: ["MessageRegistry"]),
        .executable(name: "MessageRegistryDemo", targets: ["MessageRegistryDemo"]),
    ],
    dependencies: [
        .package(path: "../Logging"),
        .package(path: "../Serialization"),
    ],
    targets: [
        .target(
            name: "MessageRegistry",
            dependencies: ["Logging", "Serialization"],
            resources: [.copy("Resources/builtins")],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .unsafeFlags(["-strict-concurrency=complete"]),
            ]
        ),
        .testTarget(
            name: "MessageRegistryTests",
            dependencies: ["MessageRegistry"],
            resources: [.copy("Fixtures")],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .executableTarget(
            name: "MessageRegistryDemo",
            dependencies: ["MessageRegistry"],
            path: "Demo/MessageRegistryDemo"
        ),
    ]
)
