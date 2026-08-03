// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ServiceCallService",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "ServiceCallService", targets: ["ServiceCallService"]),
    ],
    dependencies: [
        .package(path: "../Transport"),
    ],
    targets: [
        .target(
            name: "ServiceCallService",
            dependencies: ["Transport"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .unsafeFlags(["-strict-concurrency=complete"]),
            ]
        ),
    ]
)
