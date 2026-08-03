// swift-tools-version: 6.0
import PackageDescription

// Min macOS: .v15 (Sequoia) fallback floor per 08-tech-stack §18.
// Primary target macOS 26 Tahoe; gate Liquid Glass / Metal 4 behind #available(macOS 26, *).
//
// Vendoring note (08-tech-stack §9): SwiftCBOR and MessagePack.swift are pinned
// to upstream for Week 1. Fork both into the org and pin by SHA before v1.0.
let package = Package(
    name: "Serialization",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "Serialization", targets: ["Serialization"]),
        .executable(name: "SerializationDemo", targets: ["SerializationDemo"]),
    ],
    dependencies: [
        .package(path: "../Logging"),
        .package(url: "https://github.com/valpackett/SwiftCBOR", from: "0.4.0"),
        .package(url: "https://github.com/hirotakan/MessagePacker", from: "0.4.0"),
    ],
    targets: [
        .target(
            name: "Serialization",
            dependencies: [
                "Logging",
                "SwiftCBOR",
                .product(name: "MessagePacker", package: "MessagePacker"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .unsafeFlags(["-strict-concurrency=complete"]),
            ]
        ),
        .testTarget(
            name: "SerializationTests",
            dependencies: ["Serialization"],
            resources: [.copy("Fixtures")],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .executableTarget(
            name: "SerializationDemo",
            dependencies: ["Serialization"],
            path: "Demo/SerializationDemo"
        ),
    ]
)
