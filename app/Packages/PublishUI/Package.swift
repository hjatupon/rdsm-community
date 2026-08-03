// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PublishUI",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "PublishUI", targets: ["PublishUI"]),
    ],
    dependencies: [
        .package(path: "../Transport"),
        .package(path: "../PublishService"),
    ],
    targets: [
        .target(
            name: "PublishUI",
            dependencies: ["Transport", "PublishService"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .unsafeFlags(["-strict-concurrency=complete"]),
            ]
        ),
    ]
)
