// swift-tools-version: 6.0
import PackageDescription

// M16 ProfileStore — Layer 3 (Domain). Persists connection profiles to JSON on disk.
let package = Package(
    name: "ProfileStore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "ProfileStore", targets: ["ProfileStore"]),
    ],
    dependencies: [
        .package(path: "../Logging"),
    ],
    targets: [
        .target(
            name: "ProfileStore",
            dependencies: ["Logging"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .unsafeFlags(["-strict-concurrency=complete"]),
            ]
        ),
        .executableTarget(
            name: "ProfileDemo",
            dependencies: ["ProfileStore"],
            path: "Demo/ProfileDemo",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "ProfileStoreTests",
            dependencies: ["ProfileStore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
