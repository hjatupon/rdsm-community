// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PublishService",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "PublishService", targets: ["PublishService"]),
    ],
    dependencies: [
        .package(path: "../Logging"),
        .package(path: "../Transport"),
    ],
    targets: [
        .target(
            name: "PublishService",
            dependencies: ["Logging", "Transport"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .unsafeFlags(["-strict-concurrency=complete"]),
            ]
        ),
    ]
)
