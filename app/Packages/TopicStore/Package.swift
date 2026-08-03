// swift-tools-version: 6.0
import PackageDescription

// M12 TopicStore — Layer 3 (Domain). Central data hub: multiplexes Transport
// subscriptions, caches per-topic ring buffers, exposes typed AsyncStreams to UI.
// Contracts: C1 (per-topic message order), C3 (callbacks on actor, not MainActor),
//            C5 (Transport ↔ MCAPReader substitutable), C8 (registry frozen at use).
let package = Package(
    name: "TopicStore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "TopicStore", targets: ["TopicStore"]),
    ],
    dependencies: [
        .package(path: "../Logging"),
        .package(path: "../Transport"),
        .package(path: "../MessageRegistry"),
    ],
    targets: [
        .target(
            name: "TopicStore",
            dependencies: ["Logging", "Transport", "MessageRegistry"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .unsafeFlags(["-strict-concurrency=complete"]),
            ]
        ),
        .testTarget(
            name: "TopicStoreTests",
            dependencies: ["TopicStore", "Transport", "MessageRegistry"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
    ]
)
