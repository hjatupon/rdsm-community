import Foundation
import Metal
import MetalKit
@preconcurrency import ModelIO
import MetalCore
import Logging
import simd

/// Loads STL, OBJ, and COLLADA (.dae) mesh files into GPU-ready ``LoadedMesh`` values.
///
/// ## Supported formats (0.1.0)
/// - STL (binary and ASCII)
/// - OBJ (with MTL sidecar)
/// - COLLADA / DAE
///
/// glTF (.gltf / .glb) is deferred to 0.2.0 (requires GLTFKit2).
///
/// ## Vertex layout (stride = 32 bytes)
/// | Offset | Type   | Semantic  |
/// |--------|--------|-----------|
/// | 0      | float3 | position  |
/// | 12     | float3 | normal    |
/// | 24     | float2 | texcoord  |
public struct MeshLoader: Sendable {

    // MARK: - Supported formats

    public static let supportedExtensions: Set<String> = ["stl", "obj", "dae"]

    // MARK: - State

    private let context: MetalContext
    private let logger: any LoggerProtocol

    // MARK: - Init

    public init(context: MetalContext, logger: any LoggerProtocol = NullLogger()) {
        self.context = context
        self.logger = logger
    }

    // MARK: - Public API

    /// Loads the mesh at `url` into a ``LoadedMesh``.
    ///
    /// - Throws: ``MeshLoaderError``
    public func load(from url: URL) throws -> LoadedMesh {
        try validated(url: url)
        logger.debug("MeshLoader: loading \(url.lastPathComponent)", fields: [])
        return try loadViaModelIO(url: url, targetVertexCount: nil)
    }

    /// Loads the mesh and simplifies it toward `targetVertexCount` vertices.
    ///
    /// ModelIO doesn't ship a general-purpose decimation API; this method loads
    /// at full resolution for 0.1.0 and logs a warning if the mesh exceeds the
    /// target. Proper triangle reduction is scheduled for 0.2.0.
    public func loadOptimized(from url: URL, simplifyTo targetVertexCount: Int) throws -> LoadedMesh {
        try validated(url: url)
        logger.debug(
            "MeshLoader: loading optimized \(url.lastPathComponent) → ≤\(targetVertexCount) verts",
            fields: [])
        let mesh = try loadViaModelIO(url: url, targetVertexCount: targetVertexCount)
        if mesh.vertexCount > targetVertexCount {
            logger.warning(
                "MeshLoader: \(url.lastPathComponent) has \(mesh.vertexCount) verts (target \(targetVertexCount)); decimation deferred to 0.2.0",
                fields: [])
        }
        return mesh
    }

    // MARK: - Private helpers

    private func validated(url: URL) throws {
        let ext = url.pathExtension.lowercased()
        guard MeshLoader.supportedExtensions.contains(ext) else {
            throw MeshLoaderError.unsupportedFormat(ext)
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw MeshLoaderError.fileNotFound(url)
        }
    }

    private func loadViaModelIO(url: URL, targetVertexCount: Int?) throws -> LoadedMesh {
        let allocator = MTKMeshBufferAllocator(device: context.device)
        let vertexDescriptor = makeVertexDescriptor()

        let asset = MDLAsset(
            url: url,
            vertexDescriptor: vertexDescriptor,
            bufferAllocator: allocator)

        guard let mdlMesh = firstMDLMesh(in: asset) else {
            throw MeshLoaderError.emptyMesh(url)
        }

        // Ensure normals exist (STL often omits them)
        if !hasAttribute(MDLVertexAttributeNormal, in: mdlMesh) {
            mdlMesh.addNormals(withAttributeNamed: MDLVertexAttributeNormal, creaseThreshold: 0.5)
        }

        let mtkMesh: MTKMesh
        do {
            mtkMesh = try MTKMesh(mesh: mdlMesh, device: context.device)
        } catch {
            throw MeshLoaderError.loadFailed(url, error.localizedDescription)
        }

        guard !mtkMesh.submeshes.isEmpty,
              let vertexBuffer = mtkMesh.vertexBuffers.first?.buffer else {
            throw MeshLoaderError.emptyMesh(url)
        }

        let submeshes = mtkMesh.submeshes.enumerated().map { (i, sub) -> LoadedMesh.Submesh in
            let mdlSub = mdlMesh.submeshes?[i] as? MDLSubmesh
            let material = extractMaterial(from: mdlSub?.material)
            return LoadedMesh.Submesh(
                indexBuffer: sub.indexBuffer.buffer,
                indexCount: sub.indexCount,
                indexType: sub.indexType,
                material: material,
                primitiveType: sub.primitiveType)
        }

        let bbox = computeBoundingBox(vertexBuffer: vertexBuffer, vertexCount: mtkMesh.vertexCount)

        logger.info(
            "MeshLoader: loaded \(url.lastPathComponent) — \(mtkMesh.vertexCount) verts, \(submeshes.count) submeshes",
            fields: [])

        return LoadedMesh(
            vertexBuffer: vertexBuffer,
            vertexCount: mtkMesh.vertexCount,
            submeshes: submeshes,
            boundingBox: bbox,
            sourceURL: url)
    }

    private func makeVertexDescriptor() -> MDLVertexDescriptor {
        let desc = MDLVertexDescriptor()
        desc.attributes[0] = MDLVertexAttribute(
            name: MDLVertexAttributePosition,
            format: .float3,
            offset: 0,
            bufferIndex: 0)
        desc.attributes[1] = MDLVertexAttribute(
            name: MDLVertexAttributeNormal,
            format: .float3,
            offset: 12,
            bufferIndex: 0)
        desc.attributes[2] = MDLVertexAttribute(
            name: MDLVertexAttributeTextureCoordinate,
            format: .float2,
            offset: 24,
            bufferIndex: 0)
        desc.layouts[0] = MDLVertexBufferLayout(stride: 32)
        return desc
    }

    private func firstMDLMesh(in asset: MDLAsset) -> MDLMesh? {
        for i in 0..<asset.count {
            if let mesh = findMesh(in: asset.object(at: i)) { return mesh }
        }
        return asset.childObjects(of: MDLMesh.self).first as? MDLMesh
    }

    private func findMesh(in object: MDLObject) -> MDLMesh? {
        if let mesh = object as? MDLMesh { return mesh }
        for child in object.children.objects {
            if let mesh = findMesh(in: child) { return mesh }
        }
        return nil
    }

    private func hasAttribute(_ name: String, in mesh: MDLMesh) -> Bool {
        mesh.vertexDescriptor.attributes
            .compactMap { $0 as? MDLVertexAttribute }
            .contains { $0.name == name }
    }

    private func extractMaterial(from mdlMaterial: MDLMaterial?) -> Material {
        guard let mat = mdlMaterial else { return .default }
        var baseColor = SIMD4<Float>(0.8, 0.8, 0.8, 1.0)
        var metallic: Float = 0.0
        var roughness: Float = 0.8

        if let prop = mat.property(with: .baseColor) {
            if prop.type == .float4 {
                let v = prop.float4Value
                baseColor = SIMD4(v.x, v.y, v.z, v.w)
            } else if prop.type == .float3 {
                let v = prop.float3Value
                baseColor = SIMD4(v.x, v.y, v.z, 1.0)
            }
        }
        if let prop = mat.property(with: .metallic), prop.type == .float {
            metallic = prop.floatValue
        }
        if let prop = mat.property(with: .roughness), prop.type == .float {
            roughness = prop.floatValue
        }
        return Material(name: mat.name, baseColor: baseColor, metallic: metallic, roughness: roughness)
    }

    private func computeBoundingBox(vertexBuffer: MTLBuffer, vertexCount: Int) -> LoadedMesh.BoundingBox {
        let stride = 32
        guard vertexCount > 0, vertexBuffer.length >= stride * vertexCount else {
            return LoadedMesh.BoundingBox(min: .zero, max: .zero)
        }
        let ptr = vertexBuffer.contents().bindMemory(to: Float.self, capacity: stride * vertexCount / 4)
        var minV = SIMD3<Float>(repeating: Float.greatestFiniteMagnitude)
        var maxV = SIMD3<Float>(repeating: -Float.greatestFiniteMagnitude)
        for i in 0..<vertexCount {
            let base = i * stride / 4
            let p = SIMD3<Float>(ptr[base], ptr[base + 1], ptr[base + 2])
            minV = simd_min(minV, p)
            maxV = simd_max(maxV, p)
        }
        return LoadedMesh.BoundingBox(min: minV, max: maxV)
    }
}

// MARK: - NullLogger

public struct NullLogger: LoggerProtocol, Sendable {
    public init() {}
    public func debug(_ message: String, fields: [LogField]) {}
    public func info(_ message: String, fields: [LogField]) {}
    public func warning(_ message: String, fields: [LogField]) {}
    public func error(_ message: String, fields: [LogField]) {}
}
