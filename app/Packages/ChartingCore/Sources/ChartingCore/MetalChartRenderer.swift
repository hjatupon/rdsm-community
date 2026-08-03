import Foundation
import Logging
import Metal
import MetalCore
import MetalKit
import simd

/// MTKViewDelegate that renders all series in a `ChartView` as Metal line-strip draws.
///
/// Compiles `Chart.metal` from source at init (the same pattern used by
/// `RobotModelRenderer` and `PointCloudRenderer` in this project — SwiftPM copies
/// `.metal` files verbatim into the resource bundle rather than compiling them).
final class MetalChartRenderer: NSObject, MTKViewDelegate, @unchecked Sendable {
    private let context: MetalContext
    private let pipelineState: MTLRenderPipelineState
    private let logger: any LoggerProtocol

    // Written on the main thread (SwiftUI update path); read on the render thread
    // (MTKView delegate is also called on the main thread, so this is safe).
    var series: [ChartSeries] = []
    var window: TimeInterval = 10.0
    var valueRange: ClosedRange<Double> = -1.0 ... 1.0

    init(context: MetalContext, pixelFormat: MTLPixelFormat) throws {
        self.context = context
        self.logger = Logger(subsystem: "studio.ros2", category: "charting-metal")

        // Load and compile Chart.metal from the SPM resource bundle at runtime.
        guard let url = Bundle.module.url(forResource: "Chart", withExtension: "metal") else {
            throw ChartingError.shaderCompilationFailed("Chart.metal not found in Bundle.module")
        }
        let source: String
        do {
            source = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw ChartingError.shaderCompilationFailed("Could not read Chart.metal: \(error)")
        }
        let library: MTLLibrary
        do {
            library = try context.device.makeLibrary(source: source, options: nil)
        } catch {
            throw ChartingError.shaderCompilationFailed(error.localizedDescription)
        }

        guard let vertFn = library.makeFunction(name: "chartVertex"),
              let fragFn = library.makeFunction(name: "chartFragment") else {
            throw ChartingError.shaderCompilationFailed("chartVertex/chartFragment not found in Chart.metal")
        }

        let vtxDesc = MTLVertexDescriptor()
        vtxDesc.attributes[0].format = .float2
        vtxDesc.attributes[0].offset = 0
        vtxDesc.attributes[0].bufferIndex = 0
        vtxDesc.layouts[0].stride = MemoryLayout<SIMD2<Float>>.stride

        let pDesc = MTLRenderPipelineDescriptor()
        pDesc.vertexFunction = vertFn
        pDesc.fragmentFunction = fragFn
        pDesc.vertexDescriptor = vtxDesc
        pDesc.colorAttachments[0].pixelFormat = pixelFormat

        do {
            self.pipelineState = try context.device.makeRenderPipelineState(descriptor: pDesc)
        } catch {
            throw ChartingError.shaderCompilationFailed(error.localizedDescription)
        }

        super.init()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let descriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let commandBuffer = context.commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)
        else { return }

        encoder.setRenderPipelineState(pipelineState)

        let now = Date().timeIntervalSince1970
        let tMax = Float(now)
        let tMin = Float(now - window)
        let vMin = Float(valueRange.lowerBound)
        let vMax = Float(valueRange.upperBound)

        for s in series {
            let points = s.buffer.snapshot(maxCount: 4096)
            guard points.count >= 2 else { continue }

            let vertices = points.map { SIMD2<Float>(Float($0.t), Float($0.value)) }
            let byteCount = vertices.count * MemoryLayout<SIMD2<Float>>.stride

            guard let vtxBuffer = context.device.makeBuffer(
                bytes: vertices,
                length: byteCount,
                options: .storageModeShared
            ) else {
                logger.warning("vertex buffer allocation failed", fields: [
                    LogField(key: "series", value: s.id),
                    LogField(key: "bytes", value: "\(byteCount)")
                ])
                continue
            }

            var uniforms = ChartUniforms(
                tMin: tMin, tMax: tMax,
                vMin: vMin, vMax: vMax,
                color: s.color,
                lineWidth: 1.5)

            encoder.setVertexBuffer(vtxBuffer, offset: 0, index: 0)
            encoder.setVertexBytes(&uniforms,
                                   length: MemoryLayout<ChartUniforms>.stride,
                                   index: 1)
            encoder.drawPrimitives(type: .lineStrip,
                                   vertexStart: 0,
                                   vertexCount: vertices.count)
        }

        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
