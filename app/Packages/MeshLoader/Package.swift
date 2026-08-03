// swift-tools-version: 6.0
import PackageDescription

// M11 MeshLoader — Layer 2 (Data & Parsing). Loads STL/OBJ/DAE mesh files via
// ModelIO into MTLBuffers ready for M6 RobotModelRenderer. Depends on MetalCore (M4)
// for the device/allocator. glTF deferred to 0.2.0 (GLTFKit2).
// Contract: MeshLoader never drives a render loop — it produces LoadedMesh values only.
let package = Package(
    name: "MeshLoader",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "MeshLoader", targets: ["MeshLoader"]),
    ],
    dependencies: [
        .package(path: "../Logging"),
        .package(path: "../MetalCore"),
    ],
    targets: [
        .target(
            name: "MeshLoader",
            dependencies: ["Logging", "MetalCore"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .unsafeFlags(["-strict-concurrency=complete"]),
            ]
        ),
        .testTarget(
            name: "MeshLoaderTests",
            dependencies: ["MeshLoader", "MetalCore"],
            resources: [.copy("Fixtures")],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
    ]
)
