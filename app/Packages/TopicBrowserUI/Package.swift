// swift-tools-version: 6.0
import PackageDescription

// M18 TopicBrowserUI — Layer 4 (Feature UI). Sidebar topic list with search,
// type-filter, and schema-family icons. Selection binding lets the parent decide
// what to do with the chosen topic (inspector, 3D viewer, plotter, etc.).
let package = Package(
    name: "TopicBrowserUI",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "TopicBrowserUI", targets: ["TopicBrowserUI"]),
        .executable(name: "TopicBrowserUIDemo", targets: ["TopicBrowserUIDemo"]),
    ],
    dependencies: [
        .package(path: "../Transport"),
        .package(path: "../MessageRegistry"),
        .package(path: "../TopicStore"),
    ],
    targets: [
        .target(
            name: "TopicBrowserUI",
            dependencies: ["Transport", "TopicStore"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .unsafeFlags(["-strict-concurrency=complete"]),
            ]
        ),
        .executableTarget(
            name: "TopicBrowserUIDemo",
            dependencies: ["TopicBrowserUI", "Transport", "MessageRegistry", "TopicStore"],
            path: "Demo/TopicBrowserUIDemo",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "TopicBrowserUITests",
            dependencies: ["TopicBrowserUI", "Transport"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
