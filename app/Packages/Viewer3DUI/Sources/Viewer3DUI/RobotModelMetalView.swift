import SwiftUI
import MetalKit
import MetalCore
import RobotModelRenderer

/// NSViewRepresentable wrapping an `MTKView` driven by a `RobotModelRenderer`.
///
/// See `PointCloudMetalView` for the thread-safety rationale on `@unchecked Sendable`.
struct RobotModelMetalView: NSViewRepresentable {
    nonisolated(unsafe) let renderer: RobotModelRenderer
    let context: MetalContext
    let jointState: JointState

    func makeNSView(context ctx: Context) -> MTKView {
        let view = MTKView()
        view.device = context.device
        view.colorPixelFormat = .bgra8Unorm
        view.depthStencilPixelFormat = .depth32Float
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        view.delegate = ctx.coordinator
        view.preferredFramesPerSecond = 60
        return view
    }

    func updateNSView(_ nsView: MTKView, context ctx: Context) {
        ctx.coordinator.jointState = jointState
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(renderer: renderer, context: context, jointState: jointState)
    }

    final class Coordinator: NSObject, MTKViewDelegate, @unchecked Sendable {
        let renderer: RobotModelRenderer
        let context: MetalContext
        var jointState: JointState

        init(renderer: RobotModelRenderer, context: MetalContext, jointState: JointState) {
            self.renderer = renderer
            self.context = context
            self.jointState = jointState
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        func draw(in view: MTKView) {
            guard let cmd = context.commandQueue.makeCommandBuffer() else { return }
            renderer.render(state: jointState, view: view, in: cmd)
            if let drawable = view.currentDrawable { cmd.present(drawable) }
            cmd.commit()
        }
    }
}
