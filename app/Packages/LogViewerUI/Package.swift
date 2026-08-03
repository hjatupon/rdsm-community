// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LogViewerUI",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "LogViewerUI", targets: ["LogViewerUI"]),
    ],
    dependencies: [
        .package(path: "../LogStore"),
    ],
    targets: [
        .target(
            name: "LogViewerUI",
            dependencies: ["LogStore"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .unsafeFlags(["-strict-concurrency=complete"]),
            ]
        ),
    ]
)
