import SwiftUI
import MetalKit
import MetalCore
import PointCloudRenderer
import RobotModelRenderer

/// NSViewRepresentable wrapping an `MTKView` driven by a `PointCloudRenderer`
/// and optionally a `RobotModelRenderer` for in-scene robot rendering.
///
/// When a `robotRenderer` is provided, both renderers share a single Metal
/// render pass so the robot model appears inside the same 3D viewport as the
/// point cloud layers, using the same camera.
struct PointCloudMetalView: NSViewRepresentable {
    nonisolated(unsafe) let renderer: PointCloudRenderer
    let context: MetalContext
    let colorMode: PointColorMode
    let activeTool: CameraTool
    var onNavGoalSelected: ((Float, Float, Float) -> Void)?
    var onPoseEstimateSelected: ((Float, Float, Float, Bool) -> Void)?
    var onKeyActivatePoseEstimate: (() -> Void)?
    var onFrameSelected: ((String?) -> Void)?
    var tfFrameWorldPositions: [(id: String, metal: SIMD3<Float>)] = []
    /// When set, the robot model is rendered in the same pass (in-scene overlay).
    nonisolated(unsafe) var robotRenderer: RobotModelRenderer?
    var jointState: JointState = .zero
    /// Max points before stride-decimation. Updated live from PerformanceStore.
    var lodThreshold: Int = 500_000
    /// Target MTKView frame rate. Updated live from PerformanceStore.
    var renderFPS: Int = 60
    /// Metal drawable resolution as a fraction of native Retina scale (1.0 = full, 0.5 = half).
    /// Reduces GPU pixel fill on Retina Macs; clamped to minimum 1.0 contentsScale.
    var renderResolution: Double = 0.75
    /// Called on every Metal frame draw. Used by PerformanceDashboard to measure actual FPS.
    var onFrameDrawn: (() -> Void)?

    func makeNSView(context ctx: Context) -> MTKView {
        let view = CameraControlMTKView()
        view.device = context.device
        view.colorPixelFormat = .bgra8Unorm
        view.depthStencilPixelFormat = .depth32Float
        view.clearColor = MTLClearColor(red: 0.04, green: 0.04, blue: 0.06, alpha: 1)
        view.delegate = ctx.coordinator
        view.preferredFramesPerSecond = 60
        view.coordinator = ctx.coordinator
        return view
    }

    func updateNSView(_ nsView: MTKView, context ctx: Context) {
        let toolChanged = ctx.coordinator.activeTool != activeTool
        ctx.coordinator.colorMode             = colorMode
        ctx.coordinator.activeTool            = activeTool
        ctx.coordinator.onNavGoalSelected            = onNavGoalSelected
        ctx.coordinator.onPoseEstimateSelected       = onPoseEstimateSelected
        ctx.coordinator.onKeyActivatePoseEstimate    = onKeyActivatePoseEstimate
        ctx.coordinator.onFrameSelected              = onFrameSelected
        ctx.coordinator.tfFrameWorldPositions = tfFrameWorldPositions
        ctx.coordinator.robotRenderer         = robotRenderer
        ctx.coordinator.jointState            = jointState
        ctx.coordinator.onFrameDrawn = onFrameDrawn
        ctx.coordinator.renderer.lodThreshold = lodThreshold
        if nsView.preferredFramesPerSecond != renderFPS {
            nsView.preferredFramesPerSecond = renderFPS
        }
        let nativeScale = nsView.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
        let targetScale = max(1.0, nativeScale * renderResolution)
        if abs((nsView.layer?.contentsScale ?? nativeScale) - targetScale) > 0.01 {
            nsView.layer?.contentsScale = targetScale
        }
        if toolChanged {
            nsView.window?.invalidateCursorRects(for: nsView)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(renderer: renderer, context: context, colorMode: colorMode, activeTool: activeTool)
    }

    final class Coordinator: NSObject, MTKViewDelegate, @unchecked Sendable {
        let renderer: PointCloudRenderer
        let context: MetalContext
        var colorMode: PointColorMode
        var activeTool: CameraTool
        var onNavGoalSelected: ((Float, Float, Float) -> Void)?
        var onPoseEstimateSelected: ((Float, Float, Float, Bool) -> Void)?
        var onKeyActivatePoseEstimate: (() -> Void)?
        var onFrameSelected: ((String?) -> Void)?
        var tfFrameWorldPositions: [(id: String, metal: SIMD3<Float>)] = []
        /// Robot model renderer (optional — nil when robot model is disabled).
        var robotRenderer: RobotModelRenderer?
        var jointState: JointState = .zero
        var onFrameDrawn: (() -> Void)?

        init(renderer: PointCloudRenderer, context: MetalContext,
             colorMode: PointColorMode, activeTool: CameraTool) {
            self.renderer   = renderer
            self.context    = context
            self.colorMode  = colorMode
            self.activeTool = activeTool
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        func draw(in view: MTKView) {
            onFrameDrawn?()
            guard let cmd = context.commandQueue.makeCommandBuffer() else { return }

            if let rr = robotRenderer, rr.isModelSet {
                // Shared pass: create one encoder, draw both renderers
                guard let passDesc = view.currentRenderPassDescriptor,
                      let encoder = cmd.makeRenderCommandEncoder(descriptor: passDesc)
                else { return }
                let size = view.drawableSize
                let aspect = size.height > 0 ? Float(size.width / size.height) : 1
                let (vp, camPos) = renderer.cameraViewProjection(aspect: aspect)

                renderer.render(into: encoder, viewSize: size, mode: colorMode, cmd: cmd)
                rr.render(state: jointState, into: encoder, viewProjection: vp, cameraPosition: camPos, viewSize: size)

                encoder.endEncoding()
                if let drawable = view.currentDrawable { cmd.present(drawable) }
                cmd.commit()
            } else {
                // Point cloud only (existing fast path)
                renderer.render(view: view, mode: colorMode, in: cmd)
                if let drawable = view.currentDrawable { cmd.present(drawable) }
                cmd.commit()
            }
        }

        // MARK: - Camera input (main thread)

        var orbitModifiers: NSEvent.ModifierFlags = []

        func handleDragStart() {
            renderer.recenterPivot()
        }

        func handleDrag(deltaX: Float, deltaY: Float) {
            switch activeTool {
            case .yaw:   renderer.yaw(deltaX: deltaX)
            case .pitch: renderer.pitch(deltaY: -deltaY)
            case .roll:  renderer.roll(deltaX: deltaX)
            case .pan:   renderer.pan(deltaX: deltaX, deltaY: deltaY)
            case .orbit:
                if orbitModifiers.contains(.shift) {
                    renderer.pan(deltaX: deltaX, deltaY: deltaY)
                } else if orbitModifiers.contains(.option) {
                    renderer.roll(deltaX: deltaX)
                } else {
                    renderer.yaw(deltaX: deltaX)
                    renderer.pitch(deltaY: -deltaY)
                }
            case .navGoal:
                break
            case .poseEstimate:
                break
            }
        }

        func handleScroll(delta: Float) {
            guard abs(delta) > 0.001 else { return }
            let factor = exp(delta * 0.12)
            renderer.zoom(factor: factor)
        }

        // MARK: - Nav Goal state

        var navGoalStartScreen: CGPoint = .zero
        var navGoalDragScreen:  CGPoint = .zero

        func updateNavGoalPreview(viewSize: CGSize) {
            guard let startWorld = renderer.unprojectOntoGroundPlane(
                screenPoint: navGoalStartScreen, viewSize: viewSize) else { return }

            let hasDrag = hypot(navGoalDragScreen.x - navGoalStartScreen.x,
                                navGoalDragScreen.y - navGoalStartScreen.y) > 4
            let yaw: Float
            if hasDrag, let dragWorld = renderer.unprojectOntoGroundPlane(
                screenPoint: navGoalDragScreen, viewSize: viewSize) {
                let hdx = dragWorld.x - startWorld.x
                let hdz = dragWorld.y - startWorld.y
                yaw = atan2(-hdx, hdz)
            } else {
                yaw = 0
            }
            renderNavGoalArrow(x: startWorld.x, z: startWorld.y, yaw: yaw)
        }

        func finaliseNavGoal(viewSize: CGSize) {
            guard let startWorld = renderer.unprojectOntoGroundPlane(
                screenPoint: navGoalStartScreen, viewSize: viewSize) else { return }

            let hasDrag = hypot(navGoalDragScreen.x - navGoalStartScreen.x,
                                navGoalDragScreen.y - navGoalStartScreen.y) > 4
            let yaw: Float
            if hasDrag, let dragWorld = renderer.unprojectOntoGroundPlane(
                screenPoint: navGoalDragScreen, viewSize: viewSize) {
                let hdx = dragWorld.x - startWorld.x
                let hdz = dragWorld.y - startWorld.y
                yaw = atan2(-hdx, hdz)
            } else {
                yaw = 0
            }
            renderNavGoalArrow(x: startWorld.x, z: startWorld.y, yaw: yaw)
            onNavGoalSelected?(startWorld.x, startWorld.y, yaw)
        }

        private func renderNavGoalArrow(x: Float, z: Float, yaw: Float) {
            let shaftLength: Float  = 0.6
            let headLength: Float   = 0.25
            let lateralSize: Float  = 0.12
            let arrowY: Float       = 0.05
            let nShaft = 20
            let nHead  = 16

            var posBytes = Data(capacity: (nShaft + nHead * 2) * 12)

            let fwdX = -sin(yaw)
            let fwdZ = cos(yaw)
            let perpX = -fwdZ
            let perpZ =  fwdX

            func appendPoint(_ px: Float, _ pz: Float) {
                var vx = px, vy = arrowY, vz = pz
                withUnsafeBytes(of: &vx) { posBytes.append(contentsOf: $0) }
                withUnsafeBytes(of: &vy) { posBytes.append(contentsOf: $0) }
                withUnsafeBytes(of: &vz) { posBytes.append(contentsOf: $0) }
            }

            for i in 0..<nShaft {
                let t = Float(i) / Float(nShaft - 1) * (shaftLength - headLength)
                appendPoint(x + fwdX * t, z + fwdZ * t)
            }

            let baseX = x + fwdX * (shaftLength - headLength)
            let baseZ = z + fwdZ * (shaftLength - headLength)
            let tipX  = x + fwdX * shaftLength
            let tipZ  = z + fwdZ * shaftLength

            for i in 0..<nHead {
                let t = Float(i) / Float(nHead - 1)
                let px = (1 - t) * (baseX + perpX * lateralSize) + t * tipX
                let pz = (1 - t) * (baseZ + perpZ * lateralSize) + t * tipZ
                appendPoint(px, pz)
            }
            for i in 0..<nHead {
                let t = Float(i) / Float(nHead - 1)
                let px = (1 - t) * (baseX - perpX * lateralSize) + t * tipX
                let pz = (1 - t) * (baseZ - perpZ * lateralSize) + t * tipZ
                appendPoint(px, pz)
            }

            let totalPoints = nShaft + nHead * 2
            let frame = PointCloudFrame(
                pointCount: totalPoints,
                positions: posBytes,
                intensities: nil,
                colors: nil,
                pointSize: 5.0,
                colorMode: .constant(SIMD4<Float>(0.18, 0.85, 0.35, 1.0)))
            renderer.update(topic: "__nav_goal_arrow__", frame: frame)
        }

        // MARK: - Pose Estimate state

        var poseEstimateStartScreen: CGPoint = .zero
        var poseEstimateDragScreen:  CGPoint = .zero

        func updatePoseEstimatePreview(viewSize: CGSize) {
            guard let startWorld = renderer.unprojectOntoGroundPlane(
                screenPoint: poseEstimateStartScreen, viewSize: viewSize) else { return }

            let hasDrag = hypot(poseEstimateDragScreen.x - poseEstimateStartScreen.x,
                                poseEstimateDragScreen.y - poseEstimateStartScreen.y) > 4
            let yaw: Float
            if hasDrag, let dragWorld = renderer.unprojectOntoGroundPlane(
                screenPoint: poseEstimateDragScreen, viewSize: viewSize) {
                let hdx = dragWorld.x - startWorld.x
                let hdz = dragWorld.y - startWorld.y
                yaw = atan2(-hdx, hdz)
            } else {
                yaw = 0
            }
            renderer.update(topic: "__pose_estimate_arrow__",
                            frame: makePoseEstimateArrowFrame(x: startWorld.x, z: startWorld.y, yaw: yaw, alpha: 1.0))
            renderer.update(topic: "__pose_estimate_circle__",
                            frame: makeCovarianceCircleFrame(x: startWorld.x, z: startWorld.y, radiusMeters: 0.5, alpha: 1.0))
        }

        func finalisePoseEstimate(viewSize: CGSize) {
            guard let startWorld = renderer.unprojectOntoGroundPlane(
                screenPoint: poseEstimateStartScreen, viewSize: viewSize) else { return }

            let hasDrag = hypot(poseEstimateDragScreen.x - poseEstimateStartScreen.x,
                                poseEstimateDragScreen.y - poseEstimateStartScreen.y) > 4
            let yaw: Float
            if hasDrag, let dragWorld = renderer.unprojectOntoGroundPlane(
                screenPoint: poseEstimateDragScreen, viewSize: viewSize) {
                let hdx = dragWorld.x - startWorld.x
                let hdz = dragWorld.y - startWorld.y
                yaw = atan2(-hdx, hdz)
            } else {
                yaw = 0
            }
            renderer.update(topic: "__pose_estimate_arrow__",
                            frame: makePoseEstimateArrowFrame(x: startWorld.x, z: startWorld.y, yaw: yaw, alpha: 1.0))
            renderer.update(topic: "__pose_estimate_circle__",
                            frame: makeCovarianceCircleFrame(x: startWorld.x, z: startWorld.y, radiusMeters: 0.5, alpha: 1.0))
            onPoseEstimateSelected?(startWorld.x, startWorld.y, yaw, !hasDrag)
        }

        func selectNearestFrame(clickScreen: CGPoint, viewSize: CGSize) {
            guard let onFrameSelected else { return }
            guard !tfFrameWorldPositions.isEmpty else { return }
            var bestName: String?
            var bestDist: CGFloat = 20  // 20px hit threshold
            for entry in tfFrameWorldPositions {
                guard let screenPt = renderer.projectToScreen(entry.metal, viewSize: viewSize) else { continue }
                let dx = screenPt.x - clickScreen.x
                let dy = screenPt.y - clickScreen.y
                let dist = sqrt(dx * dx + dy * dy)
                if dist < bestDist {
                    bestDist = dist
                    bestName = entry.id
                }
            }
            onFrameSelected(bestName)
        }
    }
}

// MARK: - Pose estimate geometry builders (file-scope so Coordinator and View can both use them)

/// Builds a PointCloudFrame for a teal arrow representing a pose estimate.
func makePoseEstimateArrowFrame(x: Float, z: Float, yaw: Float, alpha: Float) -> PointCloudFrame {
    let shaftLength: Float  = 0.6
    let headLength: Float   = 0.25
    let lateralSize: Float  = 0.12
    let arrowY: Float       = 0.05
    let nShaft = 20
    let nHead  = 16

    var posBytes = Data(capacity: (nShaft + nHead * 2) * 12)

    let fwdX = -sin(yaw)
    let fwdZ = cos(yaw)
    let perpX = -fwdZ
    let perpZ =  fwdX

    func appendPoint(_ px: Float, _ pz: Float) {
        var vx = px, vy = arrowY, vz = pz
        withUnsafeBytes(of: &vx) { posBytes.append(contentsOf: $0) }
        withUnsafeBytes(of: &vy) { posBytes.append(contentsOf: $0) }
        withUnsafeBytes(of: &vz) { posBytes.append(contentsOf: $0) }
    }

    for i in 0..<nShaft {
        let t = Float(i) / Float(nShaft - 1) * (shaftLength - headLength)
        appendPoint(x + fwdX * t, z + fwdZ * t)
    }

    let baseX = x + fwdX * (shaftLength - headLength)
    let baseZ = z + fwdZ * (shaftLength - headLength)
    let tipX  = x + fwdX * shaftLength
    let tipZ  = z + fwdZ * shaftLength

    for i in 0..<nHead {
        let t = Float(i) / Float(nHead - 1)
        let px = (1 - t) * (baseX + perpX * lateralSize) + t * tipX
        let pz = (1 - t) * (baseZ + perpZ * lateralSize) + t * tipZ
        appendPoint(px, pz)
    }
    for i in 0..<nHead {
        let t = Float(i) / Float(nHead - 1)
        let px = (1 - t) * (baseX - perpX * lateralSize) + t * tipX
        let pz = (1 - t) * (baseZ - perpZ * lateralSize) + t * tipZ
        appendPoint(px, pz)
    }

    let totalPoints = nShaft + nHead * 2
    return PointCloudFrame(
        pointCount: totalPoints,
        positions: posBytes,
        intensities: nil,
        colors: nil,
        pointSize: 5.0,
        colorMode: .constant(SIMD4<Float>(0.18, 0.73, 0.69, alpha)))
}

/// Builds a PointCloudFrame for a dashed covariance circle (two arcs with gaps).
func makeCovarianceCircleFrame(x: Float, z: Float, radiusMeters: Float, alpha: Float) -> PointCloudFrame {
    let circleY: Float = 0.04
    let nArc = 32
    let gapAngle: Float = .pi / 16

    var posBytes = Data(capacity: nArc * 2 * 12)

    func appendPoint(_ px: Float, _ pz: Float) {
        var vx = px, vy = circleY, vz = pz
        withUnsafeBytes(of: &vx) { posBytes.append(contentsOf: $0) }
        withUnsafeBytes(of: &vy) { posBytes.append(contentsOf: $0) }
        withUnsafeBytes(of: &vz) { posBytes.append(contentsOf: $0) }
    }

    // Arc 1: gapAngle/2 → π - gapAngle/2
    for i in 0..<nArc {
        let t = Float(i) / Float(nArc - 1)
        let angle = gapAngle / 2 + t * (.pi - gapAngle)
        appendPoint(x + cos(angle) * radiusMeters, z + sin(angle) * radiusMeters)
    }
    // Arc 2: π + gapAngle/2 → 2π - gapAngle/2
    for i in 0..<nArc {
        let t = Float(i) / Float(nArc - 1)
        let angle = .pi + gapAngle / 2 + t * (.pi - gapAngle)
        appendPoint(x + cos(angle) * radiusMeters, z + sin(angle) * radiusMeters)
    }

    return PointCloudFrame(
        pointCount: nArc * 2,
        positions: posBytes,
        intensities: nil,
        colors: nil,
        pointSize: 3.0,
        colorMode: .constant(SIMD4<Float>(0.18, 0.73, 0.69, alpha)))
}

// MARK: - Mouse-aware MTKView subclass

private final class CameraControlMTKView: MTKView {
    weak var coordinator: PointCloudMetalView.Coordinator?
    private var mouseDownPoint: CGPoint?

    override var acceptsFirstResponder: Bool { true }

    override func resetCursorRects() {
        if coordinator?.activeTool == .navGoal || coordinator?.activeTool == .poseEstimate {
            addCursorRect(bounds, cursor: .crosshair)
        } else {
            super.resetCursorRects()
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        guard let c = coordinator else { return }
        let pt = convert(event.locationInWindow, from: nil)
        mouseDownPoint = pt
        if c.activeTool == .navGoal {
            let flipped = CGPoint(x: pt.x, y: bounds.height - pt.y)
            c.navGoalStartScreen = flipped
            c.navGoalDragScreen  = flipped
        } else if c.activeTool == .poseEstimate {
            let flipped = CGPoint(x: pt.x, y: bounds.height - pt.y)
            c.poseEstimateStartScreen = flipped
            c.poseEstimateDragScreen  = flipped
        } else {
            c.handleDragStart()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let c = coordinator else { return }
        if c.activeTool == .navGoal {
            let pt = convert(event.locationInWindow, from: nil)
            let flipped = CGPoint(x: pt.x, y: bounds.height - pt.y)
            c.navGoalDragScreen = flipped
            c.updateNavGoalPreview(viewSize: bounds.size)
        } else if c.activeTool == .poseEstimate {
            let pt = convert(event.locationInWindow, from: nil)
            let flipped = CGPoint(x: pt.x, y: bounds.height - pt.y)
            c.poseEstimateDragScreen = flipped
            c.updatePoseEstimatePreview(viewSize: bounds.size)
        } else {
            c.orbitModifiers = event.modifierFlags
            c.handleDrag(deltaX: Float(event.deltaX), deltaY: Float(event.deltaY))
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard let c = coordinator else { return }
        if c.activeTool == .navGoal {
            c.finaliseNavGoal(viewSize: bounds.size)
        } else if c.activeTool == .poseEstimate {
            c.finalisePoseEstimate(viewSize: bounds.size)
        } else if let downPt = mouseDownPoint {
            let upPt = convert(event.locationInWindow, from: nil)
            let dx = upPt.x - downPt.x
            let dy = upPt.y - downPt.y
            let dragDist = sqrt(dx * dx + dy * dy)
            mouseDownPoint = nil
            if dragDist < 5 {
                let clickY = bounds.height - upPt.y
                c.selectNearestFrame(clickScreen: CGPoint(x: upPt.x, y: clickY), viewSize: bounds.size)
            }
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        coordinator?.handleDragStart()
    }

    override func rightMouseDragged(with event: NSEvent) {
        guard let c = coordinator else { return }
        if c.activeTool == .orbit {
            c.renderer.yaw(deltaX: Float(event.deltaX))
            c.renderer.pitch(deltaY: -Float(event.deltaY))
        }
    }

    override func scrollWheel(with event: NSEvent) {
        coordinator?.handleScroll(delta: Float(event.deltaY))
    }

    override func keyDown(with event: NSEvent) {
        if event.charactersIgnoringModifiers?.lowercased() == "e" {
            coordinator?.onKeyActivatePoseEstimate?()
            return
        }
        super.keyDown(with: event)
    }
}
