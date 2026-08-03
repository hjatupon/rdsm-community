// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ServiceCallUI",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "ServiceCallUI", targets: ["ServiceCallUI"]),
    ],
    dependencies: [
        .package(path: "../ServiceCallService"),
        .package(path: "../InspectorUI"),
    ],
    targets: [
        .target(
            name: "ServiceCallUI",
            dependencies: ["ServiceCallService", "InspectorUI"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .unsafeFlags(["-strict-concurrency=complete"]),
            ]
        ),
    ]
)
