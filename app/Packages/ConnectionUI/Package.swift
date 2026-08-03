// swift-tools-version: 6.0
import PackageDescription

// M17 ConnectionUI — Layer 4 (Feature UI). Connection form, profile picker,
// and status badge. Depends on ConnectionManager + ProfileStore; never touches
// Transport directly — all wire protocol stays below the actor boundary.
let package = Package(
    name: "ConnectionUI",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "ConnectionUI", targets: ["ConnectionUI"]),
        .executable(name: "ConnectionUIDemo", targets: ["ConnectionUIDemo"]),
    ],
    dependencies: [
        .package(path: "../Logging"),
        .package(path: "../Transport"),
        .package(path: "../ConnectionManager"),
        .package(path: "../ProfileStore"),
    ],
    targets: [
        .target(
            name: "ConnectionUI",
            dependencies: ["Logging", "Transport", "ConnectionManager", "ProfileStore"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .unsafeFlags(["-strict-concurrency=complete"]),
            ]
        ),
        .executableTarget(
            name: "ConnectionUIDemo",
            dependencies: ["ConnectionUI", "Transport"],
            path: "Demo/ConnectionUIDemo",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "ConnectionUITests",
            dependencies: ["ConnectionUI"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
