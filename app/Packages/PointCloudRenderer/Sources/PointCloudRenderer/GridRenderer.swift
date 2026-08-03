import Foundation
import Metal
import MetalCore
import simd

/// Renders a finite flat reference plane in the XZ plane at Y=0.
///
/// A clean single A4-page-sheet placed on the floor of the 3D world — a faint
/// filled surface with a crisp perimeter outline. No internal grid lines.
/// 3D data layers render above the sheet.
///
/// Thread safety: `render(encoder:vp:)` is render-thread-only. `isVisible` is
/// set from the main thread only; no concurrent writes occur during rendering.
public final class GridRenderer {

    // MARK: - Configuration

    /// Half-extent of the sheet (metres). Sheet spans ±extent on both X and Z.
    public var extent: Float = 5.0

    /// When false the sheet is completely skipped during render.
    public var isVisible: Bool = true

    // MARK: - Private

    private let context: MetalContext
    private let outlinePipeline: MTLRenderPipelineState
    private let fillPipeline: MTLRenderPipelineState
    private let depthState: MTLDepthStencilState

    /// Pre-allocated buffers (reused every frame via `.contents()`).
    private let quadBuffer: MTLBuffer
    private let outlineBuffer: MTLBuffer

    // MARK: - Init

    public init(context: MetalContext) throws {
        self.context = context

        let library: MTLLibrary
        if let lib = try? context.device.makeDefaultLibrary(bundle: Bundle.module) {
            library = lib
        } else if let url = Bundle.module.url(forResource: "Grid", withExtension: "metal") {
            let source = try String(contentsOf: url, encoding: .utf8)
            library = try context.device.makeLibrary(source: source, options: nil)
        } else {
            throw MetalError.libraryNotFound("Grid shaders not found in bundle")
        }

        guard let vertFn = library.makeFunction(name: "gridVertex"),
              let fragFn = library.makeFunction(name: "gridFragment")
        else {
            throw MetalError.shaderCompilationFailed("gridVertex/gridFragment missing")
        }

        func applyBlending(_ desc: MTLRenderPipelineDescriptor) {
            desc.colorAttachments[0].pixelFormat = .bgra8Unorm
            desc.colorAttachments[0].isBlendingEnabled           = true
            desc.colorAttachments[0].rgbBlendOperation           = .add
            desc.colorAttachments[0].alphaBlendOperation         = .add
            desc.colorAttachments[0].sourceRGBBlendFactor        = .sourceAlpha
            desc.colorAttachments[0].sourceAlphaBlendFactor      = .one
            desc.colorAttachments[0].destinationRGBBlendFactor   = .oneMinusSourceAlpha
            desc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
            desc.depthAttachmentPixelFormat = .depth32Float
        }

        let outlineDesc = MTLRenderPipelineDescriptor()
        outlineDesc.vertexFunction   = vertFn
        outlineDesc.fragmentFunction = fragFn
        applyBlending(outlineDesc)
        outlinePipeline = try context.device.makeRenderPipelineState(descriptor: outlineDesc)

        let fillDesc = MTLRenderPipelineDescriptor()
        fillDesc.vertexFunction   = vertFn
        fillDesc.fragmentFunction = fragFn
        applyBlending(fillDesc)
        fillPipeline = try context.device.makeRenderPipelineState(descriptor: fillDesc)

        let depthDesc = MTLDepthStencilDescriptor()
        depthDesc.depthCompareFunction = .lessEqual
        depthDesc.isDepthWriteEnabled  = false
        guard let ds = context.device.makeDepthStencilState(descriptor: depthDesc) else {
            throw MetalError.shaderCompilationFailed("grid depth-stencil creation failed")
        }
        depthState = ds

        // Pre-allocate reusable vertex buffers (geometry is fixed-size).
        let quadVerts: [SIMD3<Float>] = [
            SIMD3<Float>(-1, 0, -1), SIMD3<Float>(1, 0, -1), SIMD3<Float>(-1, 0, 1),
            SIMD3<Float>( 1, 0, -1), SIMD3<Float>(1, 0,  1), SIMD3<Float>(-1, 0, 1)
        ]
        guard let qb = context.device.makeBuffer(
            bytes: quadVerts, length: quadVerts.count * MemoryLayout<SIMD3<Float>>.stride,
            options: .storageModeManaged)
        else { throw MetalError.bufferAllocationFailed(length: quadVerts.count * MemoryLayout<SIMD3<Float>>.stride) }
        quadBuffer = qb

        let outlineVerts: [SIMD3<Float>] = [
            SIMD3<Float>(-1, 0, -1), SIMD3<Float>( 1, 0, -1),
            SIMD3<Float>( 1, 0, -1), SIMD3<Float>( 1, 0,  1),
            SIMD3<Float>( 1, 0,  1), SIMD3<Float>(-1, 0,  1),
            SIMD3<Float>(-1, 0,  1), SIMD3<Float>(-1, 0, -1)
        ]
        guard let ob = context.device.makeBuffer(
            bytes: outlineVerts, length: outlineVerts.count * MemoryLayout<SIMD3<Float>>.stride,
            options: .storageModeManaged)
        else { throw MetalError.bufferAllocationFailed(length: outlineVerts.count * MemoryLayout<SIMD3<Float>>.stride) }
        outlineBuffer = ob
    }

    // MARK: - Render

    /// Draw the floor sheet + perimeter outline into an already-opened encoder.
    /// Call from `PointCloudRenderer.render()` BEFORE the point-cloud draw.
    public func render(encoder: MTLRenderCommandEncoder, vp: simd_float4x4) {
        guard isVisible else { return }
        encoder.setDepthStencilState(depthState)

        let scale = extent

        // ── Pass 1: filled sheet quad ────────────────────────────────────────
        var scaleMat = float4x4(diagonal: SIMD4<Float>(scale, 1, scale, 1))
        var fillMVP = vp * scaleMat
        var fillUniforms = GridUniforms(
            mvp: fillMVP,
            color: SIMD4<Float>(0.50, 0.52, 0.56, 0.25))

        encoder.setRenderPipelineState(fillPipeline)
        encoder.setVertexBuffer(quadBuffer, offset: 0, index: 0)
        encoder.setVertexBytes(&fillUniforms,
                               length: MemoryLayout<GridUniforms>.stride,
                               index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)

        // ── Pass 2: perimeter outline (4 edges) ──────────────────────────────
        scaleMat = float4x4(diagonal: SIMD4<Float>(scale, 1, scale, 1))
        var outlineMVP = vp * scaleMat
        var outlineUniforms = GridUniforms(
            mvp: outlineMVP,
            color: SIMD4<Float>(0.55, 0.57, 0.60, 0.50))

        encoder.setRenderPipelineState(outlinePipeline)
        encoder.setVertexBuffer(outlineBuffer, offset: 0, index: 0)
        encoder.setVertexBytes(&outlineUniforms,
                               length: MemoryLayout<GridUniforms>.stride,
                               index: 1)
        encoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: 8)
    }

    // MARK: - Private helpers

    private struct GridUniforms {
        var mvp: simd_float4x4
        var color: SIMD4<Float>
    }
}
