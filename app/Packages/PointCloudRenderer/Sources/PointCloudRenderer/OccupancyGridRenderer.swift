import Foundation
import Metal
import MetalCore
import simd

// One vertex on the CPU side: packed float3 position + RGBA8 color.
// Matches `struct OccupancyGridVertex` in OccupancyGrid.metal.
private struct OGVertex {
    var x, y, z: Float
    var r, g, b, a: UInt8
}

// Matches `struct OccupancyGridUniforms` in OccupancyGrid.metal.
private struct OGUniforms {
    var mvp: simd_float4x4
}

/// Thread-safe store of the latest OccupancyGrid quad mesh for each topic.
private final class OGFrameStore: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String: OGEntry] = [:]

    struct OGEntry {
        let vertexBuffer: MTLBuffer
        let indexBuffer: MTLBuffer
        let indexCount: Int
    }

    func store(topic: String, entry: OGEntry) {
        lock.withLock { entries[topic] = entry }
    }

    func remove(topic: String) {
        lock.withLock { entries[topic] = nil }
    }

    func clearAll() {
        lock.withLock { entries.removeAll() }
    }

    func snapshot() -> [OGEntry] {
        lock.withLock { Array(entries.values) }
    }
}

/// Renders OccupancyGrid messages as world-space filled quads (one quad per cell).
///
/// Must be called from the same render pass as `PointCloudRenderer` so the two
/// renderers share the depth buffer and points render on top of the map.
/// `render(into:vp:)` should be called BEFORE the point-cloud draw.
final class OccupancyGridRenderer: @unchecked Sendable {

    private let context: MetalContext
    private let pipeline: MTLRenderPipelineState
    private let depthState: MTLDepthStencilState
    private let store = OGFrameStore()

    init(context: MetalContext) throws {
        self.context = context

        let library: MTLLibrary
        if let lib = try? context.device.makeDefaultLibrary(bundle: Bundle.module) {
            library = lib
        } else if let url = Bundle.module.url(forResource: "OccupancyGrid", withExtension: "metal") {
            let source = try String(contentsOf: url, encoding: .utf8)
            library = try context.device.makeLibrary(source: source, options: nil)
        } else {
            throw MetalError.libraryNotFound("OccupancyGrid shaders not found in bundle")
        }

        guard let vertFn = library.makeFunction(name: "occupancyGridVertex"),
              let fragFn = library.makeFunction(name: "occupancyGridFragment")
        else {
            throw MetalError.shaderCompilationFailed("occupancyGridVertex/occupancyGridFragment missing")
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
            throw MetalError.shaderCompilationFailed("OccupancyGrid depth-stencil creation failed")
        }
        depthState = ds
    }

    /// Build GPU buffers from the cell data and store them for the next render frame.
    ///
    /// - Parameters:
    ///   - topic: Unique key (layer UUID string) for this map layer.
    ///   - cells: Flat occupancy values (row-major). -1 = unknown, 0 = free, 1-100 = occupied.
    ///   - width: Number of columns.
    ///   - resolution: Cell side length in metres.
    ///   - originX: Map origin X in ROS coordinates.
    ///   - originY: Map origin Y in ROS coordinates.
    ///   - originRotation: Map origin quaternion (ix, iy, iz, r) for non-axis-aligned maps.
    ///   - tintColor: RGBA (0–1) tint applied to occupied cells. Free/unknown cells are unaffected.
    ///   - showUnknownCells: When false, unknown (-1) cells are skipped entirely.
    func update(
        topic: String,
        cells: [Int],
        width: Int,
        resolution: Float,
        originX: Float,
        originY: Float,
        originRotation: simd_quatf,
        tintColor: SIMD4<Float> = SIMD4<Float>(1, 1, 1, 1),
        freeColor: SIMD3<Float> = SIMD3<Float>(0.94, 0.94, 0.94),
        unknownColor: SIMD3<Float> = SIMD3<Float>(0.55, 0.65, 0.75),
        showGridLines: Bool = false,
        showUnknownCells: Bool = true
    ) {
        let cellCount = cells.count
        guard cellCount > 0, width > 0 else { return }

        let half = resolution * 0.5
        // Tiny Y offset below origin so scan points at Y≈0 always win depth.
        let mapY: Float = -0.001

        var verts = [OGVertex]()
        var indices = [UInt32]()
        verts.reserveCapacity(cellCount * 4)
        indices.reserveCapacity(cellCount * 6)

        let hasNonIdentityRotation = originRotation.angle > 1e-4

        for (i, cell) in cells.enumerated() {
            // cell: -1 = unknown, 0 = free, 1-100 = occupied. >100 = skip.
            guard cell >= -1, cell <= 100 else { continue }
            // Optionally hide unknown cells
            if cell == -1 && !showUnknownCells { continue }

            let col = i % width
            let row = i / width

            // Cell centre in ROS frame (before map-origin rotation).
            let localX = (Float(col) + 0.5) * resolution
            let localY = (Float(row) + 0.5) * resolution

            // Apply map-origin rotation if non-identity.
            let (rosX, rosY): (Float, Float)
            if hasNonIdentityRotation {
                let rotated = originRotation.act(SIMD3<Float>(localX, localY, 0))
                rosX = originX + rotated.x
                rosY = originY + rotated.y
            } else {
                rosX = originX + localX
                rosY = originY + localY
            }

            let (mx, _, mz) = swizzle(rosX, rosY, 0)

            let (dx, dz): (Float, Float)
            if hasNonIdentityRotation {
                dx = half; dz = half
            } else {
                dx = half; dz = half
            }

            let r, g, b: UInt8
            if cell == -1 {
                // Unknown: blue-gray
                r = UInt8(max(0, min(255, unknownColor.x * 255)))
                g = UInt8(max(0, min(255, unknownColor.y * 255)))
                b = UInt8(max(0, min(255, unknownColor.z * 255)))
            } else if cell == 0 {
                // Free: configurable color
                r = UInt8(max(0, min(255, freeColor.x * 255)))
                g = UInt8(max(0, min(255, freeColor.y * 255)))
                b = UInt8(max(0, min(255, freeColor.z * 255)))
            } else {
                // Occupied 1-100: scale near-black, then multiply by tint color.
                let brightness = Float(max(20, 220 - cell * 2))
                let tr = UInt8(max(0, min(255, brightness * tintColor.x)))
                let tg = UInt8(max(0, min(255, brightness * tintColor.y)))
                let tb = UInt8(max(0, min(255, brightness * tintColor.z)))
                r = tr; g = tg; b = tb
            }
            let a: UInt8 = 255

            let base = UInt32(verts.count)
            // Four corners lying flat on the Metal XZ plane (Y = mapY).
            verts.append(OGVertex(x: mx - dx, y: mapY, z: mz - dz, r: r, g: g, b: b, a: a))
            verts.append(OGVertex(x: mx + dx, y: mapY, z: mz - dz, r: r, g: g, b: b, a: a))
            verts.append(OGVertex(x: mx + dx, y: mapY, z: mz + dz, r: r, g: g, b: b, a: a))
            verts.append(OGVertex(x: mx - dx, y: mapY, z: mz + dz, r: r, g: g, b: b, a: a))
            // Two triangles per quad.
            indices.append(contentsOf: [base, base+1, base+2, base, base+2, base+3])
        }

        guard !verts.isEmpty else { store.remove(topic: topic); return }

        let vSize = verts.count * MemoryLayout<OGVertex>.stride
        let iSize = indices.count * MemoryLayout<UInt32>.stride

        guard let vBuf = context.device.makeBuffer(bytes: verts, length: vSize, options: .storageModeShared),
              let iBuf = context.device.makeBuffer(bytes: indices, length: iSize, options: .storageModeShared)
        else { return }

        store.store(topic: topic, entry: OGFrameStore.OGEntry(
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

    /// Draw all stored OccupancyGrid layers into an already-opened encoder.
    /// Call BEFORE the point-cloud draw so points render on top of the map.
    func render(into encoder: MTLRenderCommandEncoder, vp: simd_float4x4) {
        let entries = store.snapshot()
        guard !entries.isEmpty else { return }

        encoder.setRenderPipelineState(pipeline)
        encoder.setDepthStencilState(depthState)

        var uniforms = OGUniforms(mvp: vp)

        for entry in entries {
            encoder.setVertexBuffer(entry.vertexBuffer, offset: 0, index: 0)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<OGUniforms>.stride, index: 1)
            encoder.drawIndexedPrimitives(
                type: .triangle,
                indexCount: entry.indexCount,
                indexType: .uint32,
                indexBuffer: entry.indexBuffer,
                indexBufferOffset: 0)
        }
    }
}
