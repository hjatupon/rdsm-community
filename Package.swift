// swift-tools-version: 6.0
import PackageDescription

// RDSM Community — aggregate package.
// Exposes every core module as a product so downstream consumers (including the
// paid RDSM Pro build) can depend on this single package instead of vendoring
// the sources. Each target maps onto the corresponding folder under app/Packages/.
let package = Package(
    name: "RDSMCommunity",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "AppShell", targets: ["AppShell"]),
        .library(name: "ChartingCore", targets: ["ChartingCore"]),
        .library(name: "ConnectionManager", targets: ["ConnectionManager"]),
        .library(name: "ConnectionUI", targets: ["ConnectionUI"]),
        .library(name: "InspectorUI", targets: ["InspectorUI"]),
        .library(name: "LayoutEngine", targets: ["LayoutEngine"]),
        .library(name: "LogStore", targets: ["LogStore"]),
        .library(name: "LogViewerUI", targets: ["LogViewerUI"]),
        .library(name: "Logging", targets: ["Logging"]),
        .library(name: "MeshLoader", targets: ["MeshLoader"]),
        .library(name: "MessageRegistry", targets: ["MessageRegistry"]),
        .library(name: "MetalCore", targets: ["MetalCore"]),
        .library(name: "PointCloudRenderer", targets: ["PointCloudRenderer"]),
        .library(name: "ProfileStore", targets: ["ProfileStore"]),
        .library(name: "PublishService", targets: ["PublishService"]),
        .library(name: "PublishUI", targets: ["PublishUI"]),
        .library(name: "RobotModelCore", targets: ["RobotModelCore"]),
        .library(name: "RobotModelLoader", targets: ["RobotModelLoader"]),
        .library(name: "RobotModelRenderer", targets: ["RobotModelRenderer"]),
        .library(name: "Serialization", targets: ["Serialization"]),
        .library(name: "ServiceCallService", targets: ["ServiceCallService"]),
        .library(name: "ServiceCallUI", targets: ["ServiceCallUI"]),
        .library(name: "TFTree", targets: ["TFTree"]),
        .library(name: "TopicBrowserUI", targets: ["TopicBrowserUI"]),
        .library(name: "TopicStore", targets: ["TopicStore"]),
        .library(name: "Transport", targets: ["Transport"]),
        .library(name: "URDFParser", targets: ["URDFParser"]),
        .library(name: "Viewer3DUI", targets: ["Viewer3DUI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/valpackett/SwiftCBOR", from: "0.4.0"),
        .package(url: "https://github.com/hirotakan/MessagePacker", from: "0.4.0"),
    ],
    targets: [
        .target(
            name: "AppShell",
            dependencies: ["Logging", "Transport", "MessageRegistry", "TopicStore", "TFTree", "ConnectionManager", "ConnectionUI", "LayoutEngine", "ProfileStore", "LogStore", "LogViewerUI", "MetalCore", "MeshLoader", "RobotModelCore", "RobotModelLoader", "RobotModelRenderer", "URDFParser", "PublishService", "PublishUI", "TopicBrowserUI", "ServiceCallService", "ServiceCallUI", "InspectorUI", "Viewer3DUI"],
            path: "app/Packages/AppShell/Sources/AppShell",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .unsafeFlags(["-strict-concurrency=complete"]),
            ]
        ),
        .target(
            name: "ChartingCore",
            dependencies: ["MetalCore", "Logging"],
            path: "app/Packages/ChartingCore/Sources/ChartingCore",
            resources: [.process("Shaders")],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .unsafeFlags(["-strict-concurrency=complete"]),
            ]
        ),
        .target(
            name: "ConnectionManager",
            dependencies: ["Logging", "Transport"],
            path: "app/Packages/ConnectionManager/Sources/ConnectionManager",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .unsafeFlags(["-strict-concurrency=complete"]),
            ]
        ),
        .target(
            name: "ConnectionUI",
            dependencies: ["Logging", "Transport", "ConnectionManager", "ProfileStore"],
            path: "app/Packages/ConnectionUI/Sources/ConnectionUI",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .unsafeFlags(["-strict-concurrency=complete"]),
            ]
        ),
        .target(
            name: "InspectorUI",
            dependencies: ["Transport", "MessageRegistry", "TopicStore", "ChartingCore", "MetalCore", "LogStore"],
            path: "app/Packages/InspectorUI/Sources/InspectorUI",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .unsafeFlags(["-strict-concurrency=complete"]),
            ]
        ),
        .target(
            name: "LayoutEngine",
            dependencies: ["Logging"],
            path: "app/Packages/LayoutEngine/Sources/LayoutEngine",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .unsafeFlags(["-strict-concurrency=complete"]),
            ]
        ),
        .target(
            name: "LogStore",
            dependencies: ["Logging", "TopicStore"],
            path: "app/Packages/LogStore/Sources/LogStore",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .unsafeFlags(["-strict-concurrency=complete"]),
            ]
        ),
        .target(
            name: "LogViewerUI",
            dependencies: ["LogStore"],
            path: "app/Packages/LogViewerUI/Sources/LogViewerUI",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .unsafeFlags(["-strict-concurrency=complete"]),
            ]
        ),
        .target(
            name: "Logging",
            path: "app/Packages/Logging/Sources/Logging",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .unsafeFlags(["-strict-concurrency=complete"]),
            ]
        ),
        .target(
            name: "MeshLoader",
            dependencies: ["Logging", "MetalCore"],
            path: "app/Packages/MeshLoader/Sources/MeshLoader",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .unsafeFlags(["-strict-concurrency=complete"]),
            ]
        ),
        .target(
            name: "MessageRegistry",
            dependencies: ["Logging", "Serialization"],
            path: "app/Packages/MessageRegistry/Sources/MessageRegistry",
            resources: [.copy("Resources/builtins")],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .unsafeFlags(["-strict-concurrency=complete"]),
            ]
        ),
        .target(
            name: "MetalCore",
            dependencies: ["Logging"],
            path: "app/Packages/MetalCore/Sources/MetalCore",
            resources: [.process("Shaders")],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .unsafeFlags(["-strict-concurrency=complete"]),
            ]
        ),
        .target(
            name: "PointCloudRenderer",
            dependencies: ["MetalCore", "Logging"],
            path: "app/Packages/PointCloudRenderer/Sources/PointCloudRenderer",
            resources: [.process("Shaders")],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .unsafeFlags(["-strict-concurrency=complete"]),
            ]
        ),
        .target(
            name: "ProfileStore",
            dependencies: ["Logging"],
            path: "app/Packages/ProfileStore/Sources/ProfileStore",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .unsafeFlags(["-strict-concurrency=complete"]),
            ]
        ),
        .target(
            name: "PublishService",
            dependencies: ["Logging", "Transport"],
            path: "app/Packages/PublishService/Sources/PublishService",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .unsafeFlags(["-strict-concurrency=complete"]),
            ]
        ),
        .target(
            name: "PublishUI",
            dependencies: ["Transport", "PublishService"],
            path: "app/Packages/PublishUI/Sources/PublishUI",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .unsafeFlags(["-strict-concurrency=complete"]),
            ]
        ),
        .target(
            name: "RobotModelCore",
            path: "app/Packages/RobotModelCore/Sources/RobotModelCore",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .unsafeFlags(["-strict-concurrency=complete"]),
            ]
        ),
        .target(
            name: "RobotModelLoader",
            dependencies: ["Logging", "MetalCore", "URDFParser", "RobotModelCore", "MeshLoader"],
            path: "app/Packages/RobotModelLoader/Sources/RobotModelLoader",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .unsafeFlags(["-strict-concurrency=complete"]),
            ]
        ),
        .target(
            name: "RobotModelRenderer",
            dependencies: ["MetalCore", "Logging", "RobotModelCore", "MeshLoader", "PointCloudRenderer"],
            path: "app/Packages/RobotModelRenderer/Sources/RobotModelRenderer",
            resources: [.process("Shaders")],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .unsafeFlags(["-strict-concurrency=complete"]),
            ]
        ),
        .target(
            name: "Serialization",
            dependencies: ["Logging", .product(name: "SwiftCBOR", package: "SwiftCBOR"), .product(name: "MessagePacker", package: "MessagePacker")],
            path: "app/Packages/Serialization/Sources/Serialization",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .unsafeFlags(["-strict-concurrency=complete"]),
            ]
        ),
        .target(
            name: "ServiceCallService",
            dependencies: ["Transport"],
            path: "app/Packages/ServiceCallService/Sources/ServiceCallService",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .unsafeFlags(["-strict-concurrency=complete"]),
            ]
        ),
        .target(
            name: "ServiceCallUI",
            dependencies: ["ServiceCallService", "InspectorUI"],
            path: "app/Packages/ServiceCallUI/Sources/ServiceCallUI",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .unsafeFlags(["-strict-concurrency=complete"]),
            ]
        ),
        .target(
            name: "TFTree",
            dependencies: ["Logging"],
            path: "app/Packages/TFTree/Sources/TFTree",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .unsafeFlags(["-strict-concurrency=complete"]),
            ]
        ),
        .target(
            name: "TopicBrowserUI",
            dependencies: ["Transport", "MessageRegistry", "TopicStore"],
            path: "app/Packages/TopicBrowserUI/Sources/TopicBrowserUI",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .unsafeFlags(["-strict-concurrency=complete"]),
            ]
        ),
        .target(
            name: "TopicStore",
            dependencies: ["Logging", "Transport", "MessageRegistry"],
            path: "app/Packages/TopicStore/Sources/TopicStore",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .unsafeFlags(["-strict-concurrency=complete"]),
            ]
        ),
        .target(
            name: "Transport",
            dependencies: ["Logging", "Serialization"],
            path: "app/Packages/Transport/Sources/Transport",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .unsafeFlags(["-strict-concurrency=complete"]),
            ]
        ),
        .target(
            name: "URDFParser",
            dependencies: ["Logging", "RobotModelCore"],
            path: "app/Packages/URDFParser/Sources/URDFParser",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .unsafeFlags(["-strict-concurrency=complete"]),
            ]
        ),
        .target(
            name: "Viewer3DUI",
            dependencies: ["Logging", "Transport", "MessageRegistry", "TopicStore", "TFTree", "MetalCore", "PointCloudRenderer", "RobotModelRenderer", "URDFParser", "MeshLoader", "PublishService"],
            path: "app/Packages/Viewer3DUI/Sources/Viewer3DUI",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .unsafeFlags(["-strict-concurrency=complete"]),
            ]
        ),
    ]
)
