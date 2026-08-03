// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LogStore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "LogStore", targets: ["LogStore"]),
    ],
    dependencies: [
        .package(path: "../Logging"),
        .package(path: "../TopicStore"),
    ],
    targets: [
        .target(
            name: "LogStore",
            dependencies: ["Logging", "TopicStore"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .unsafeFlags(["-strict-concurrency=complete"]),
            ]
        ),
    ]
)
