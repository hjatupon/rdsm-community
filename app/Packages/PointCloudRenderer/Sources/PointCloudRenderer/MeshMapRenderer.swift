import Foundation
import Metal
import MetalCore
import simd

// MARK: - Mesh Map Renderer

/// Renders triangle mesh maps loaded from PLY/OBJ files.
///
/// Supports:
/// - PLY (ASCII + binary little-endian)
/// - OBJ (with vertex normals)
/// - Face-colored or tint-colored rendering
/// - Directional lighting for surface detail
/// - Wireframe overlay option
/// - LOD stride
final class MeshMapRenderer: @unchecked Sendable {

    private let context: MetalContext
    private let pipeline: MTLRenderPipelineState
    private let depthState: MTLDepthStencilState
    private let store = MeshFrameStore()

    init(context: MetalContext) throws {
        self.context = context

        let library: MTLLibrary
        if let lib = try? context.device.makeDefaultLibrary(bundle: Bundle.module) {
            library = lib
        } else if let url = Bundle.module.url(forResource: "MeshMap", withExtension: "metal") {
            let source = try String(contentsOf: url, encoding: .utf8)
            library = try context.device.makeLibrary(source: source, options: nil)
        } else {
            throw MetalError.libraryNotFound("MeshMap shaders not found in bundle")
        }

        guard let vertFn = library.makeFunction(name: "meshMapVertex"),
              let fragFn = library.makeFunction(name: "meshMapFragment")
        else {
            throw MetalError.shaderCompilationFailed("meshMapVertex/meshMapFragment missing")
        }

        let pipelineDesc = MTLRenderPipelineDescriptor()
        pipelineDesc.vertexFunction   = vertFn
        pipelineDesc.fragmentFunction = fragFn
        pipelineDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipelineDesc.depthAttachmentPixelFormat      = .depth32Float
        pipeline = try context.device.makeRenderPipelineState(descriptor: pipelineDesc)

        let depthDesc = MTLDepthStencilDescriptor()
        depthDesc.depthCompareFunction = .lessEqual
        depthDesc.isDepthWriteEnabled  = true
        guard let ds = context.device.makeDepthStencilState(descriptor: depthDesc) else {
            throw MetalError.shaderCompilationFailed("MeshMap depth-stencil creation failed")
        }
        depthState = ds
    }

    /// Build GPU buffers from parsed mesh data.
    ///
    /// - Parameters:
    ///   - topic: Unique key (layer UUID string).
    ///   - vertices: Interleaved position + normal + color.
    ///   - indices: Triangle indices.
    ///   - tintColor: RGBA tint applied to all vertices.
    ///   - strideN: Render every Nth triangle (1 = all).
    func update(
        topic: String,
        vertices: [MMVertex],
        indices: [UInt32],
        tintColor: SIMD4<Float> = SIMD4<Float>(0.9, 0.9, 0.9, 1.0),
        strideN: Int = 1
    ) {
        guard !vertices.isEmpty, !indices.isEmpty else {
            store.remove(topic: topic)
            return
        }

        var verts = vertices
        // Apply tint if not near-white
        if tintColor.x < 0.99 || tintColor.y < 0.99 || tintColor.z < 0.99 {
            for i in verts.indices {
                verts[i].r = UInt8(max(0, min(255, Float(verts[i].r) * tintColor.x)))
                verts[i].g = UInt8(max(0, min(255, Float(verts[i].g) * tintColor.y)))
                verts[i].b = UInt8(max(0, min(255, Float(verts[i].b) * tintColor.z)))
            }
        }

        // LOD stride
        var finalIndices = indices
        if strideN > 1 {
            finalIndices = []
            finalIndices.reserveCapacity(indices.count / strideN)
            var i = 0
            while i + 2 < indices.count {
                finalIndices.append(contentsOf: [indices[i], indices[i+1], indices[i+2]])
                i += 3 * strideN
            }
        }

        let vSize = verts.count * MemoryLayout<MMVertex>.stride
        let iSize = finalIndices.count * MemoryLayout<UInt32>.stride

        guard let vBuf = context.device.makeBuffer(bytes: verts, length: vSize, options: .storageModeShared),
              let iBuf = context.device.makeBuffer(bytes: finalIndices, length: iSize, options: .storageModeShared)
        else { return }

        store.store(topic: topic, entry: MeshFrameStore.MeshEntry(
            vertexBuffer: vBuf,
            indexBuffer: iBuf,
            indexCount: finalIndices.count))
    }

    func removeTopic(_ topic: String) {
        store.remove(topic: topic)
    }

    func clearAll() {
        store.clearAll()
    }

    func render(into encoder: MTLRenderCommandEncoder, vp: simd_float4x4) {
        let entries = store.snapshot()
        guard !entries.isEmpty else { return }

        encoder.setRenderPipelineState(pipeline)
        encoder.setDepthStencilState(depthState)

        var uniforms = MeshUniforms(
            mvp: vp,
            lightDir: SIMD3<Float>(0.3, 0.8, 0.5),
            ambient: 0.3)

        for entry in entries {
            encoder.setVertexBuffer(entry.vertexBuffer, offset: 0, index: 0)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<MeshUniforms>.stride, index: 1)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<MeshUniforms>.stride, index: 1)
            encoder.drawIndexedPrimitives(
                type: .triangle,
                indexCount: entry.indexCount,
                indexType: .uint32,
                indexBuffer: entry.indexBuffer,
                indexBufferOffset: 0)
        }
    }
}

// MARK: - Supporting Types

public struct MMVertex {
    var x, y, z: Float
    var nx, ny, nz: Float
    var r, g, b, a: UInt8

    public init(x: Float, y: Float, z: Float,
                nx: Float = 0, ny: Float = 1, nz: Float = 0,
                r: UInt8 = 200, g: UInt8 = 200, b: UInt8 = 200, a: UInt8 = 255) {
        self.x = x; self.y = y; self.z = z
        self.nx = nx; self.ny = ny; self.nz = nz
        self.r = r; self.g = g; self.b = b; self.a = a
    }
}

private struct MeshUniforms {
    var mvp: simd_float4x4
    var lightDir: SIMD3<Float>
    var ambient: Float
}

private final class MeshFrameStore: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String: MeshEntry] = [:]

    struct MeshEntry {
        let vertexBuffer: MTLBuffer
        let indexBuffer: MTLBuffer
        let indexCount: Int
    }

    func store(topic: String, entry: MeshEntry) {
        lock.withLock { entries[topic] = entry }
    }

    func remove(topic: String) {
        lock.withLock { entries[topic] = nil }
    }

    func clearAll() {
        lock.withLock { entries.removeAll() }
    }

    func snapshot() -> [MeshEntry] {
        lock.withLock { Array(entries.values) }
    }
}
