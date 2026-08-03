import Foundation
import Metal
import MetalCore
import simd

// MARK: - Octomap Renderer

/// Renders Octomap voxels as colored cubes using instanced drawing for performance.
///
/// Supports:
/// - Binary octomap data parsing (octomap_msgs/Octomap)
/// - Occupied / Free / Unknown voxel visibility toggles
/// - Configurable colors and alpha per voxel type
/// - LOD stride (render every Nth voxel)
/// - Max depth limit
final class OctomapRenderer: @unchecked Sendable {

    private let context: MetalContext
    private let pipeline: MTLRenderPipelineState
    private let depthState: MTLDepthStencilState
    private let store = OctoFrameStore()

    init(context: MetalContext) throws {
        self.context = context

        let library: MTLLibrary
        if let lib = try? context.device.makeDefaultLibrary(bundle: Bundle.module) {
            library = lib
        } else if let url = Bundle.module.url(forResource: "Octomap", withExtension: "metal") {
            let source = try String(contentsOf: url, encoding: .utf8)
            library = try context.device.makeLibrary(source: source, options: nil)
        } else {
            throw MetalError.libraryNotFound("Octomap shaders not found in bundle")
        }

        guard let vertFn = library.makeFunction(name: "octomapVertex"),
              let fragFn = library.makeFunction(name: "octomapFragment")
        else {
            throw MetalError.shaderCompilationFailed("octomapVertex/ octomapFragment missing")
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
            throw MetalError.shaderCompilationFailed("Octomap depth-stencil creation failed")
        }
        depthState = ds
    }

    /// Parse binary octomap data and build GPU buffers.
    ///
    /// - Parameters:
    ///   - topic: Unique key (layer UUID string) for this octomap layer.
    ///   - data: Raw binary octomap data (gzipped or raw).
    ///   - resolution: Voxel edge length in meters.
    ///   - showOccupied: Render occupied voxels.
    ///   - showFree: Render free voxels.
    ///   - showUnknown: Render unknown voxels.
    ///   - occupiedColor: RGBA (0–1) for occupied voxels.
    ///   - freeColor: RGBA (0–1) for free voxels.
    ///   - alpha: Overall alpha multiplier.
    ///   - strideN: Render every Nth voxel (1 = all).
    ///   - maxDepth: Maximum tree depth to render (-1 = all).
    func update(
        topic: String,
        voxels: [(x: Float, y: Float, z: Float, size: Float, occupied: Bool)],
        showOccupied: Bool = true,
        showFree: Bool = false,
        showUnknown: Bool = false,
        occupiedColor: SIMD4<Float> = SIMD4<Float>(0.2, 0.6, 0.8, 0.7),
        freeColor: SIMD4<Float> = SIMD4<Float>(0.8, 0.9, 1.0, 0.3),
        alpha: Double = 0.7,
        strideN: Int = 1
    ) {
        var verts = [OMVertex]()
        var indices = [UInt32]()
        verts.reserveCapacity(voxels.count * 24) // 6 faces × 4 verts
        indices.reserveCapacity(voxels.count * 36) // 6 faces × 2 tris × 3 indices

        for (i, voxel) in voxels.enumerated() {
            if strideN > 1 && (i % strideN) != 0 { continue }

            let show: Bool
            let color: SIMD4<Float>
            if voxel.occupied {
                show = showOccupied
                color = occupiedColor
            } else {
                show = showFree
                color = freeColor
            }
            guard show else { continue }

            let hx = voxel.size * 0.5
            let hy = voxel.size * 0.5
            let hz = voxel.size * 0.5
            let cx = voxel.x
            let cy = voxel.y
            let cz = voxel.z

            let r = UInt8(max(0, min(255, color.x * 255)))
            let g = UInt8(max(0, min(255, color.y * 255)))
            let b = UInt8(max(0, min(255, color.z * 255)))
            let a = UInt8(max(0, min(255, alpha * 255)))

            let base = UInt32(verts.count)

            // 6 faces, each a quad (4 vertices + 6 indices)
            let faceVerts: [(Float, Float, Float)] = [
                // Front
                (cx - hx, cy - hy, cz + hz), (cx + hx, cy - hy, cz + hz),
                (cx + hx, cy + hy, cz + hz), (cx - hx, cy + hy, cz + hz),
                // Back
                (cx + hx, cy - hy, cz - hz), (cx - hx, cy - hy, cz - hz),
                (cx - hx, cy + hy, cz - hz), (cx + hx, cy + hy, cz - hz),
                // Left
                (cx - hx, cy - hy, cz - hz), (cx - hx, cy - hy, cz + hz),
                (cx - hx, cy + hy, cz + hz), (cx - hx, cy + hy, cz - hz),
                // Right
                (cx + hx, cy - hy, cz + hz), (cx + hx, cy - hy, cz - hz),
                (cx + hx, cy + hy, cz - hz), (cx + hx, cy + hy, cz + hz),
                // Top
                (cx - hx, cy + hy, cz + hz), (cx + hx, cy + hy, cz + hz),
                (cx + hx, cy + hy, cz - hz), (cx - hx, cy + hy, cz - hz),
                // Bottom
                (cx - hx, cy - hy, cz - hz), (cx + hx, cy - hy, cz - hz),
                (cx + hx, cy - hy, cz + hz), (cx - hx, cy - hy, cz + hz),
            ]

            for fv in faceVerts {
                verts.append(OMVertex(x: fv.0, y: fv.1, z: fv.2, r: r, g: g, b: b, a: a))
            }

            // 6 faces × 2 triangles
            for f in 0..<6 {
                let fb = base + UInt32(f * 4)
                indices.append(contentsOf: [fb, fb+1, fb+2, fb, fb+2, fb+3])
            }
        }

        guard !verts.isEmpty else { store.remove(topic: topic); return }

        let vSize = verts.count * MemoryLayout<OMVertex>.stride
        let iSize = indices.count * MemoryLayout<UInt32>.stride

        guard let vBuf = context.device.makeBuffer(bytes: verts, length: vSize, options: .storageModeShared),
              let iBuf = context.device.makeBuffer(bytes: indices, length: iSize, options: .storageModeShared)
        else { return }

        store.store(topic: topic, entry: OctoFrameStore.OctoEntry(
            vertexBuffer: vBuf,
            indexBuffer: iBuf,
            indexCount: indices.count))
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

        var uniforms = OctoUniforms(mvp: vp)

        for entry in entries {
            encoder.setVertexBuffer(entry.vertexBuffer, offset: 0, index: 0)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<OctoUniforms>.stride, index: 1)
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

private struct OMVertex {
    var x, y, z: Float
    var r, g, b, a: UInt8
}

private struct OctoUniforms {
    var mvp: simd_float4x4
}

private final class OctoFrameStore: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String: OctoEntry] = [:]

    struct OctoEntry {
        let vertexBuffer: MTLBuffer
        let indexBuffer: MTLBuffer
        let indexCount: Int
    }

    func store(topic: String, entry: OctoEntry) {
        lock.withLock { entries[topic] = entry }
    }

    func remove(topic: String) {
        lock.withLock { entries[topic] = nil }
    }

    func clearAll() {
        lock.withLock { entries.removeAll() }
    }

    func snapshot() -> [OctoEntry] {
        lock.withLock { Array(entries.values) }
    }
}
