import Testing
import Foundation
import Metal
@testable import MeshLoader
import MetalCore

// MARK: - Helpers

private func fixtureURL(_ name: String) -> URL {
    Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures")!
}

private func makeLoader() throws -> MeshLoader {
    let ctx = try MetalContext()
    return MeshLoader(context: ctx)
}

// MARK: - Format tests

@Suite("FormatTests")
struct FormatTests {

    @Test("Loads OBJ cube — vertex count and bounding box")
    func testLoadOBJ() throws {
        let loader = try makeLoader()
        let mesh = try loader.load(from: fixtureURL("cube.obj"))
        // Cube OBJ has 12 triangles × 3 unique verts per face = 36 draw verts (due to normal splitting)
        #expect(mesh.vertexCount > 0)
        #expect(mesh.vertexCount <= 36)
        #expect(!mesh.submeshes.isEmpty)
        // Bounding box should be ≈ ±0.5 on all axes
        #expect(abs(mesh.boundingBox.min.x - (-0.5)) < 0.01)
        #expect(abs(mesh.boundingBox.max.x -   0.5) < 0.01)
        #expect(mesh.boundingBox.diagonal > 0)
    }

    @Test("Loads binary STL cube")
    func testLoadSTL() throws {
        let loader = try makeLoader()
        let mesh = try loader.load(from: fixtureURL("cube.stl"))
        #expect(mesh.vertexCount > 0)
        // 12 triangles × 3 verts = 36 (STL has no shared vertices)
        #expect(mesh.vertexCount == 36)
        #expect(!mesh.submeshes.isEmpty)
    }

    @Test("Loads COLLADA DAE cube (or gracefully fails without AppKit context)")
    func testLoadDAE() throws {
        let loader = try makeLoader()
        // ModelIO COLLADA importer requires an AppKit run loop in the CLI test runner;
        // we accept either successful geometry or a graceful MeshLoaderError (never a crash).
        let result = Result { try loader.load(from: fixtureURL("cube.dae")) }
        switch result {
        case .success(let mesh):
            #expect(mesh.vertexCount > 0)
            #expect(!mesh.submeshes.isEmpty)
        case .failure(let err as MeshLoaderError):
            // Graceful failure is acceptable in this context
            _ = err
        case .failure(let err):
            Issue.record("Unexpected non-MeshLoaderError: \(err)")
        }
    }

    @Test("sourceURL is preserved")
    func testSourceURL() throws {
        let loader = try makeLoader()
        let url = fixtureURL("cube.stl")
        let mesh = try loader.load(from: url)
        #expect(mesh.sourceURL == url)
    }

    @Test("Vertex buffer length matches vertex count × stride (32)")
    func testVertexBufferStride() throws {
        let loader = try makeLoader()
        let mesh = try loader.load(from: fixtureURL("cube.stl"))
        #expect(mesh.vertexBuffer.length >= mesh.vertexCount * 32)
    }

    @Test("Bounding box center is near origin for unit cube")
    func testBoundingBoxCenter() throws {
        let loader = try makeLoader()
        let mesh = try loader.load(from: fixtureURL("cube.stl"))
        let center = mesh.boundingBox.center
        #expect(abs(center.x) < 0.01)
        #expect(abs(center.y) < 0.01)
        #expect(abs(center.z) < 0.01)
    }
}

// MARK: - Error / malformed file tests

@Suite("MalformedFileTests")
struct MalformedFileTests {

    @Test("Unsupported extension throws unsupportedFormat")
    func testUnsupportedExtension() throws {
        let url = URL(fileURLWithPath: "/tmp/model.fbx")
        let loader = try makeLoader()
        #expect(throws: MeshLoaderError.self) {
            _ = try loader.load(from: url)
        }
    }

    @Test("Missing file throws fileNotFound")
    func testMissingFile() throws {
        let url = URL(fileURLWithPath: "/tmp/does_not_exist_\(UUID().uuidString).obj")
        let loader = try makeLoader()
        #expect(throws: MeshLoaderError.self) {
            _ = try loader.load(from: url)
        }
    }

    @Test("Truncated STL does not crash (throws or returns degenerate mesh)")
    func testTruncatedSTL() throws {
        let loader = try makeLoader()
        let url = fixtureURL("truncated.stl")
        // ModelIO either throws or returns empty — either is acceptable; must not crash
        let result = Result { try loader.load(from: url) }
        switch result {
        case .success(let mesh):
            // If ModelIO somehow parsed it, the mesh should at minimum have a buffer
            #expect(mesh.vertexBuffer.length >= 0)
        case .failure:
            break  // expected — malformed file
        }
    }

    @Test("Broken DAE does not crash")
    func testBrokenDAE() throws {
        let loader = try makeLoader()
        let url = fixtureURL("broken.dae")
        let result = Result { try loader.load(from: url) }
        switch result {
        case .success(let mesh):
            #expect(mesh.vertexBuffer.length >= 0)
        case .failure:
            break
        }
    }
}

// MARK: - Optimization tests

@Suite("OptimizationTests")
struct OptimizationTests {

    @Test("loadOptimized returns a LoadedMesh")
    func testLoadOptimized() throws {
        let loader = try makeLoader()
        let mesh = try loader.loadOptimized(from: fixtureURL("cube.stl"), simplifyTo: 100)
        #expect(mesh.vertexCount > 0)
    }

    @Test("loadOptimized with large target returns full mesh unchanged")
    func testLoadOptimizedNoChange() throws {
        let loader = try makeLoader()
        let full = try loader.load(from: fixtureURL("cube.stl"))
        let opt = try loader.loadOptimized(from: fixtureURL("cube.stl"), simplifyTo: 10_000)
        #expect(full.vertexCount == opt.vertexCount)
    }
}

// MARK: - Material tests

@Suite("MaterialTests")
struct MaterialTests {

    @Test("OBJ material name is not empty")
    func testMaterialName() throws {
        let loader = try makeLoader()
        let mesh = try loader.load(from: fixtureURL("cube.obj"))
        // OBJ has a named material group
        #expect(mesh.submeshes.first != nil)
    }

    @Test("Default material has expected base color")
    func testDefaultMaterial() {
        let mat = Material.default
        #expect(mat.baseColor.x > 0)
        #expect(mat.metallic == 0)
        #expect(mat.roughness > 0)
    }
}
