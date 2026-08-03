// swift-tools-version: 6.0
import PackageDescription

// AppShell — the shared application shell (Community). Contains the composition root,
// main window, settings, onboarding, and the plugin-registry seams. Consumed by both
// the free and paid app targets; only paid packages are absent here.
let package = Package(
    name: "AppShell",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "AppShell", targets: ["AppShell"]),
    ],
    dependencies: [
        .package(path: "../Logging"),
        .package(path: "../Transport"),
        .package(path: "../MessageRegistry"),
        .package(path: "../TopicStore"),
        .package(path: "../TFTree"),
        .package(path: "../ConnectionManager"),
        .package(path: "../ConnectionUI"),
        .package(path: "../LayoutEngine"),
        .package(path: "../ProfileStore"),
        .package(path: "../LogStore"),
        .package(path: "../LogViewerUI"),
        .package(path: "../MetalCore"),
        .package(path: "../MeshLoader"),
        .package(path: "../RobotModelCore"),
        .package(path: "../RobotModelLoader"),
        .package(path: "../RobotModelRenderer"),
        .package(path: "../URDFParser"),
        .package(path: "../PublishService"),
        .package(path: "../PublishUI"),
        .package(path: "../TopicBrowserUI"),
        .package(path: "../ServiceCallService"),
        .package(path: "../ServiceCallUI"),
        .package(path: "../InspectorUI"),
        .package(path: "../Viewer3DUI"),
    ],
    targets: [
        .target(
            name: "AppShell",
            dependencies: [
                "Logging", "Transport", "MessageRegistry", "TopicStore", "TFTree",
                "ConnectionManager", "ConnectionUI", "LayoutEngine", "ProfileStore",
                "LogStore", "LogViewerUI", "MetalCore", "MeshLoader", "RobotModelCore",
                "RobotModelLoader", "RobotModelRenderer", "URDFParser", "PublishService",
                "PublishUI", "TopicBrowserUI", "ServiceCallService", "ServiceCallUI",
                "InspectorUI", "Viewer3DUI",
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .unsafeFlags(["-strict-concurrency=complete"]),
            ]
        ),
    ]
)
