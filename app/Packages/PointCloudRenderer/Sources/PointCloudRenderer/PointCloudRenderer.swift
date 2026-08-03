import Foundation
import Logging
import Metal
import MetalCore
import MetalKit
import simd

/// Level-of-detail plan: how far to stride through the cloud so the draw stays within
/// the renderer's point budget. At or below ``threshold`` points nothing is dropped.
struct LODPlan: Equatable {
    let stride: Int
    let drawCount: Int

    /// Default above-this-count threshold for stride-decimation.
    static let defaultThreshold = 500_000

    static func make(pointCount: Int, threshold: Int = defaultThreshold) -> LODPlan {
        let count = max(0, pointCount)
        let cap = max(1, threshold)
        guard count > cap else { return LODPlan(stride: 1, drawCount: count) }
        let stride = (count + cap - 1) / cap // ceil
        let drawCount = (count + stride - 1) / stride // ceil
        return LODPlan(stride: stride, drawCount: drawCount)
    }
}

/// Bytes uploaded to the GPU for one render cycle, broken out per channel. Kept as a
/// pure function of the frame + LOD so the ≤ 16 MB budget (Milestone B) is testable
/// without a GPU.
struct BufferPlan: Equatable {
    let positionsBytes: Int
    let colorsBytes: Int
    let intensitiesBytes: Int

    var total: Int {
        positionsBytes + colorsBytes + intensitiesBytes
    }

    /// Per-cycle upload budget. Stride-decimation keeps `drawCount` ≤ 500k, so the
    /// worst case (positions 6 MB + float4 colors 8 MB) stays under this cap.
    static let cycleBudget = 16 * 1024 * 1024

    static func make(frame: PointCloudFrame, lod: LODPlan) -> BufferPlan {
        BufferPlan(
            positionsBytes: lod.drawCount * PointCloudFrame.positionStride,
            colorsBytes: frame.colors == nil ? 0 : lod.drawCount * PointCloudFrame.colorStride,
            intensitiesBytes: frame.intensities == nil ? 0 : lod.drawCount * PointCloudFrame.intensityStride)
    }
}

/// Uniform block shared with `PointCloud.metal`. Field order and offsets must match
/// the Metal `struct PointUniforms` exactly.
struct PointUniforms {
    var mvp: simd_float4x4
    var constantColor: SIMD4<Float>
    var axisMin: Float
    var axisMax: Float
    var intensityMin: Float
    var intensityMax: Float
    var colorMode: Int32
    var axisIndex: Int32
    var pointSize: Float
}

/// Lock-protected latest-frame slot (single-slot double buffer): `update` stores from
/// any thread, the render thread takes the most recent. Enforces Contract C5 —
/// `update(frame:)` is thread-safe; `render` reads on the render thread only.
final class FrameBox: @unchecked Sendable {
    private let lock = NSLock()
    private var frame: PointCloudFrame?

    func store(_ frame: PointCloudFrame) {
        lock.withLock { self.frame = frame }
    }

    func take() -> PointCloudFrame? {
        lock.withLock { frame }
    }
}

/// Lock-protected per-topic frame store enabling multi-layer compositing: each
/// subscribed topic owns one latest-frame slot; `render` draws all of them in a
/// single pass. Writes (`store`/`remove`) come from the main thread; `snapshot`
/// is read on the render thread.
final class LayeredFrameStore: @unchecked Sendable {
    private let lock = NSLock()
    private var frames: [String: PointCloudFrame] = [:]

    func store(topic: String, frame: PointCloudFrame) {
        lock.withLock { frames[topic] = frame }
    }

    func remove(topic: String) {
        lock.withLock { frames[topic] = nil }
    }

    func clearAll() {
        lock.withLock { frames.removeAll() }
    }

    func snapshot() -> [PointCloudFrame] {
        lock.withLock { Array(frames.values) }
    }
}

/// Thread-safe orbit camera state shared between the main thread (user input)
/// and the render thread (read-only via `get()`).
final class CameraBox: @unchecked Sendable {
    private let lock = NSLock()
    private var state: Camera = Camera()

    func get() -> Camera { lock.withLock { state } }
    func modify(_ fn: (inout Camera) -> Void) { lock.withLock { fn(&state) } }
}

/// Renders a point cloud with GPU point sprites, colored per ``PointColorMode``.
///
/// Ingest (``update(frame:)``) is thread-safe; ``render(view:mode:in:)`` must run on
/// the render thread (Contract C5). Position/color buffers are recycled through
/// `MetalCore.ResourcePool` and the per-cycle upload is bounded to 16 MB via
/// stride-decimation (Milestone B). The Metal 4 mesh-shader fast path is deferred
/// (PENDING-AS); the point-primitive pipeline here is correct on macOS 15+ and Intel.
public final class PointCloudRenderer {
    private let context: MetalContext
    private let pool: ResourcePool
    private let logger: any LoggerProtocol
    private let pipeline: MTLRenderPipelineState
    private let depthState: MTLDepthStencilState
    private let frameStore = LayeredFrameStore()
    private let cameraBox = CameraBox()
    private let occupancyGridRenderer: OccupancyGridRenderer?
    private let octomapRenderer: OctomapRenderer?
    private let meshMapRenderer: MeshMapRenderer?

    /// UserDefaults key used to persist the camera state between launches.
    private static let cameraDefaultsKey = "com.jatupon.ros2studio.camera"

    /// Called whenever the camera changes (orbit/pan/zoom/set). Receives the
    /// encoded camera blob so the caller can persist it per-profile. When nil,
    /// the renderer falls back to the single global UserDefaults key.
    public var onCameraChanged: ((Data) -> Void)?

    /// Maximum points rendered before stride-decimation kicks in.
    /// Updated from the main thread; read on the render thread — Int writes are atomic on arm64.
    public var lodThreshold: Int = LODPlan.defaultThreshold
    /// Timer for smooth camera animation (Jump-to-Frame).
    private var animationTimer: Timer?

    public init(context: MetalContext) throws {
        self.context = context
        pool = ResourcePool(context: context)
        logger = Logger(subsystem: "studio.ros2", category: "pointcloud")

        // Restore persisted camera state if available.
        if let data = UserDefaults.standard.data(forKey: Self.cameraDefaultsKey),
           let saved = try? JSONDecoder().decode(Camera.self, from: data) {
            cameraBox.modify { $0 = saved }
        }

        // Xcode app builds compile .metal → default.metallib inside Bundle.module.
        // SwiftPM test/CLI builds copy .metal verbatim and compile from source at runtime.
        let library: MTLLibrary
        if let lib = try? context.device.makeDefaultLibrary(bundle: Bundle.module) {
            library = lib
        } else if let url = Bundle.module.url(forResource: "PointCloud", withExtension: "metal") {
            do {
                let source = try String(contentsOf: url, encoding: .utf8)
                library = try context.device.makeLibrary(source: source, options: nil)
            } catch {
                throw MetalError.shaderCompilationFailed(error.localizedDescription)
            }
        } else {
            throw MetalError.libraryNotFound("PointCloud shaders not found in bundle")
        }
        guard let vertexFn = library.makeFunction(name: "pointVertex"),
              let fragmentFn = library.makeFunction(name: "pointFragment")
        else {
            throw MetalError.shaderCompilationFailed("pointVertex/pointFragment missing")
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFn
        descriptor.fragmentFunction = fragmentFn
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        descriptor.depthAttachmentPixelFormat = .depth32Float
        do {
            pipeline = try context.device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            throw MetalError.shaderCompilationFailed(error.localizedDescription)
        }

        let depthDescriptor = MTLDepthStencilDescriptor()
        depthDescriptor.depthCompareFunction = .lessEqual
        depthDescriptor.isDepthWriteEnabled = true
        guard let depthState = context.device.makeDepthStencilState(descriptor: depthDescriptor) else {
            throw MetalError.shaderCompilationFailed("depth-stencil state creation failed")
        }
        self.depthState = depthState

        // OccupancyGridRenderer is non-critical: failure means maps render as points (fallback).
        occupancyGridRenderer = try? OccupancyGridRenderer(context: context)
        octomapRenderer = try? OctomapRenderer(context: context)
        meshMapRenderer = try? MeshMapRenderer(context: context)
    }

    /// Thread-safe ingest of the latest frame for a named topic layer. Cheap:
    /// stores a reference, no upload. Multiple topics composite in `render`.
    public func update(topic: String, frame: PointCloudFrame) {
        guard frame.hasValidLayout else {
            logger.warning(
                "dropping malformed frame",
                fields: [LogField(key: "points", value: String(frame.pointCount))])
            return
        }
        frameStore.store(topic: topic, frame: frame)
    }

    /// Convenience for single-layer callers (demo/replay): stores to a default slot.
    public func update(frame: PointCloudFrame) {
        update(topic: "__default__", frame: frame)
    }

    /// Thread-safe ingest of an OccupancyGrid as a flat quad mesh.
    /// Replaces the previous point-sprite path for map/costmap topics.
    public func updateOccupancyGrid(
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
        occupancyGridRenderer?.update(
            topic: topic, cells: cells, width: width,
            resolution: resolution, originX: originX, originY: originY,
            originRotation: originRotation, tintColor: tintColor,
            freeColor: freeColor, unknownColor: unknownColor,
            showGridLines: showGridLines, showUnknownCells: showUnknownCells)
    }

    /// Thread-safe ingest of Octomap voxels.
    public func updateOctomap(
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
        octomapRenderer?.update(
            topic: topic, voxels: voxels,
            showOccupied: showOccupied, showFree: showFree, showUnknown: showUnknown,
            occupiedColor: occupiedColor, freeColor: freeColor,
            alpha: alpha, strideN: strideN)
    }

    /// Thread-safe ingest of a triangle mesh map.
    public func updateMeshMap(
        topic: String,
        vertices: [MMVertex],
        indices: [UInt32],
        tintColor: SIMD4<Float> = SIMD4<Float>(0.9, 0.9, 0.9, 1.0),
        strideN: Int = 1
    ) {
        meshMapRenderer?.update(
            topic: topic, vertices: vertices, indices: indices,
            tintColor: tintColor, strideN: strideN)
    }

    /// Removes a topic layer's geometry from the scene (e.g. when hidden/removed).
    public func clearTopic(_ topic: String) {
        frameStore.remove(topic: topic)
        occupancyGridRenderer?.removeTopic(topic)
        octomapRenderer?.removeTopic(topic)
        meshMapRenderer?.removeTopic(topic)
    }

    /// Clears all layers. Called when subscriptions are torn down or reconfigured.
    public func clearAllLayers() {
        frameStore.clearAll()
        occupancyGridRenderer?.clearAll()
        octomapRenderer?.clearAll()
        meshMapRenderer?.clearAll()
    }

    // MARK: - Camera control (main-thread safe)

    /// Orbit the camera by screen-space drag deltas (pixels).
    /// Legacy combined mode: changes both azimuth (yaw) and elevation (pitch).
    /// Pivot is always world origin — `target` is structurally zero; orbit never drifts.
    public func orbit(deltaX: Float, deltaY: Float) {
        cameraBox.modify { cam in
            cam.azimuth -= deltaX * 0.005
            cam.elevation = max(-.pi / 2 + 0.01, min(.pi / 2 - 0.01, cam.elevation + deltaY * 0.005))
        }
        persistCamera()
    }

    /// Yaw — rotate around the world vertical axis. Only azimuth changes.
    /// Maps stay flat-aligned; elevation is locked.
    public func yaw(deltaX: Float) {
        cameraBox.modify { cam in
            cam.azimuth -= deltaX * 0.005
        }
        persistCamera()
    }

    /// Pitch — tilt the camera up/down. Only elevation changes.
    public func pitch(deltaY: Float) {
        cameraBox.modify { cam in
            cam.elevation = max(-.pi / 2 + 0.01, min(.pi / 2 - 0.01, cam.elevation + deltaY * 0.005))
        }
        persistCamera()
    }

    /// Roll — bank the camera around the view-forward axis.
    public func roll(deltaX: Float) {
        cameraBox.modify { cam in
            cam.roll += deltaX * 0.005
        }
        persistCamera()
    }

    /// No-op — the orbit pivot is always the world origin (0,0,0) by construction.
    /// `target` is never modified by orbit/yaw/pitch/roll; `panOffset` accumulates
    /// pan gestures separately so the pivot is inherently stable without any reset.
    public func recenterPivot() {
        // Intentionally empty: pivot is structurally fixed at world origin.
    }

    /// Zoom by a multiplicative factor (> 1 = closer, < 1 = further).
    public func zoom(factor: Float) {
        cameraBox.modify { cam in
            cam.distance = max(0.05, cam.distance / max(0.001, factor))
        }
        persistCamera()
    }

    /// Pan — translate the entire camera system (eye + look-at) in screen space.
    /// Accumulates into `panOffset` so the orbit pivot (`target`) stays at world origin.
    /// Left/right moves along the camera's right axis; up/down along the camera's up axis.
    public func pan(deltaX: Float, deltaY: Float) {
        cameraBox.modify { cam in
            let speed = cam.distance * 0.001
            // Compute camera right and up vectors for screen-aligned pan.
            let cosEl = cos(cam.elevation)
            let sinEl = sin(cam.elevation)
            let cosAz = cos(cam.azimuth)
            let sinAz = sin(cam.azimuth)
            // Camera right axis (perpendicular to forward in the horizontal plane)
            let rightX =  cosAz
            let rightZ = -sinAz
            // Camera up axis (perpendicular to forward, tilted by elevation)
            let upX = -sinEl * sinAz
            let upY =  cosEl
            let upZ = -sinEl * cosAz
            cam.panOffset.x += (-deltaX * rightX + deltaY * upX) * speed
            cam.panOffset.y +=  deltaY * upY * speed
            cam.panOffset.z += (-deltaX * rightZ + deltaY * upZ) * speed
        }
        persistCamera()
    }

    /// Reset camera to an isometric view good for flat maps (azimuth 45°, elevation 35°).
    public func resetCamera() {
        cameraBox.modify { cam in
            cam = Camera(azimuth: .pi / 4, elevation: 35.0 * .pi / 180.0)
        }
        if onCameraChanged == nil {
            UserDefaults.standard.removeObject(forKey: Self.cameraDefaultsKey)
        } else {
            persistCamera()
        }
    }

    /// Smoothly animate the camera to center on a target position (Metal Y-up coordinates).
    /// Uses a Timer-based tween over ~0.35 seconds.
    public func animateToFrame(target: SIMD3<Float>, distance: Float? = nil) {
        animationTimer?.invalidate()
        animationTimer = nil

        let startCam = cameraBox.get()
        let startPan = startCam.panOffset
        let endPan = target
        let startDist = startCam.distance
        let endDist = distance ?? max(startDist, 2.0)
        let duration: TimeInterval = 0.35
        let startTime = Date()

        animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let elapsed = Date().timeIntervalSince(startTime)
            let t = min(1.0, elapsed / duration)
            let ease = 1 - pow(1 - Float(t), 3)
            let currentPan = SIMD3<Float>(
                startPan.x + (endPan.x - startPan.x) * ease,
                startPan.y + (endPan.y - startPan.y) * ease,
                startPan.z + (endPan.z - startPan.z) * ease)
            let currentDist = startDist + (endDist - startDist) * ease
            self.cameraBox.modify { cam in
                cam.panOffset = currentPan
                cam.distance = currentDist
            }
            if t >= 1.0 {
                timer.invalidate()
                self.animationTimer = nil
                self.persistCamera()
            }
        }
    }

    /// Cancels any in-progress camera animation.
    public func cancelAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
    }

    /// Switch to a top-down perspective view (high elevation, looking down at the scene).
    /// Note: uses perspective projection, not true orthographic.
    public func topView() {
        cameraBox.modify { cam in
            cam.elevation = .pi / 2 - 0.01
            cam.azimuth   = 0
            cam.roll      = 0
            cam.panOffset = .zero
        }
        persistCamera()
    }

    /// Show or hide the reference-plane grid. Persisted across calls within the session.
    public func setGridVisible(_ visible: Bool) {
        // Grid removed — the Y-up coordinate system is self-evident
    }

    /// Apply a partial camera state update.
    /// Accepts any combination of azimuth, elevation, roll, distance, targetX/Y/Z.
    /// Note: targetX/Y/Z now map to panOffset (the orbit pivot stays at world origin).
    public func setCamera(params: [String: Double]) {
        cameraBox.modify { cam in
            if let v = params["azimuth"]   { cam.azimuth      = Float(v) }
            if let v = params["elevation"] { cam.elevation     = max(-.pi / 2 + 0.01, min(.pi / 2 - 0.01, Float(v))) }
            if let v = params["roll"]      { cam.roll          = Float(v) }
            if let v = params["distance"]  { cam.distance      = max(0.05, Float(v)) }
            if let tx = params["targetX"]  { cam.panOffset.x   = Float(tx) }
            if let ty = params["targetY"]  { cam.panOffset.y   = Float(ty) }
            if let tz = params["targetZ"]  { cam.panOffset.z   = Float(tz) }
        }
        persistCamera()
    }

    /// Persist current camera state. If `onCameraChanged` is set, calls it with
    /// the encoded blob (per-profile storage); otherwise writes to the global
    /// UserDefaults key (legacy fallback).
    private func persistCamera() {
        let cam = cameraBox.get()
        guard let data = try? JSONEncoder().encode(cam) else { return }
        if let cb = onCameraChanged {
            cb(data)
        } else {
            UserDefaults.standard.set(data, forKey: Self.cameraDefaultsKey)
        }
    }

    /// Returns the current camera as a JSON-encoded blob for external persistence.
    public func cameraSnapshot() -> Data? {
        try? JSONEncoder().encode(cameraBox.get())
    }

    /// Returns the current camera azimuth (yaw) and elevation (pitch) in radians.
    /// Used by ViewCubeWidget to reflect current orientation.
    public func cameraOrientation() -> (azimuth: Float, elevation: Float) {
        let cam = cameraBox.get()
        return (cam.azimuth, cam.elevation)
    }

    /// Projects a world-space Metal point to 2D screen coordinates.
    /// Returns nil if the point is behind the near plane or outside the view.
    /// `viewSize` is the full drawable size in pixels (same as MTKView.drawableSize).
    public func projectToScreen(_ p: SIMD3<Float>, viewSize: CGSize) -> CGPoint? {
        guard viewSize.width > 0, viewSize.height > 0 else { return nil }
        let cam = cameraBox.get()
        let aspect = Float(viewSize.width / viewSize.height)
        let vp = cam.viewProjection(aspect: aspect)
        let clip = vp * SIMD4<Float>(p.x, p.y, p.z, 1)
        guard clip.w > 0 else { return nil }
        let ndcX = clip.x / clip.w
        let ndcY = clip.y / clip.w
        guard ndcX >= -1, ndcX <= 1, ndcY >= -1, ndcY <= 1 else { return nil }
        let sx = Double((ndcX + 1) * 0.5) * viewSize.width
        let sy = Double((1 - ndcY) * 0.5) * viewSize.height
        return CGPoint(x: sx, y: sy)
    }

    /// Unprojects a screen-space point (in view pixels, origin top-left) onto the
    /// world-space Y=0 ground plane (XZ plane, Metal Y-up convention). Returns
    /// `(hitX, hitZ)` in world XZ coordinates on the ground plane.
    /// Returns nil if the ray is parallel to the plane (camera looking parallel to floor).
    ///
    /// **Coordinate mapping:** All ROS data is swizzled to Metal Y-up on input, so
    /// the nav/map floor is at Y=0 (XZ plane). The Y axis is the Metal "up" direction.
    ///
    /// Used by the Nav Goal tool to convert mouse click position to world coords.
    public func unprojectOntoGroundPlane(screenPoint: CGPoint, viewSize: CGSize) -> SIMD2<Float>? {
        guard viewSize.width > 0, viewSize.height > 0 else { return nil }
        let cam = cameraBox.get()
        let aspect = Float(viewSize.width / viewSize.height)

        // NDC: x in [-1,1], y in [-1,1] (flip Y from top-left screen to bottom-left NDC)
        let ndcX = Float(screenPoint.x / viewSize.width) * 2.0 - 1.0
        let ndcY = 1.0 - Float(screenPoint.y / viewSize.height) * 2.0

        // Inverse view-projection to get ray in world space.
        let vp = cam.viewProjection(aspect: aspect)
        let vpInv = vp.inverse

        // Unproject near and far clip-space points.
        let nearClip = SIMD4<Float>(ndcX, ndcY, 0.0, 1.0)
        let farClip  = SIMD4<Float>(ndcX, ndcY, 1.0, 1.0)

        var nearWorld = vpInv * nearClip
        var farWorld  = vpInv * farClip

        // Perspective divide.
        guard nearWorld.w != 0, farWorld.w != 0 else { return nil }
        nearWorld /= nearWorld.w
        farWorld  /= farWorld.w

        // Ray: origin + t * direction, intersect with Y=0 plane (the nav/map floor).
        let rayOrigin = SIMD3<Float>(nearWorld.x, nearWorld.y, nearWorld.z)
        let rayDir    = SIMD3<Float>(farWorld.x  - nearWorld.x,
                                     farWorld.y  - nearWorld.y,
                                     farWorld.z  - nearWorld.z)

        // Plane Y=0: t = -rayOrigin.y / rayDir.y
        guard abs(rayDir.y) > 1e-6 else { return nil }
        let t = -rayOrigin.y / rayDir.y
        guard t > 0 else { return nil }

        let hitX = rayOrigin.x + t * rayDir.x
        let hitZ = rayOrigin.z + t * rayDir.z
        return SIMD2<Float>(hitX, hitZ)
    }

    /// Snaps the camera to a named standard view (SolidWorks-style ViewCube).
    /// Roll is always reset to 0 on snap. panOffset is cleared so the snap looks
    /// toward world origin regardless of any prior pan. Persists the new camera state.
    public func snapView(azimuth: Float, elevation: Float) {
        cameraBox.modify { cam in
            cam.azimuth   = azimuth
            cam.elevation = max(-.pi / 2 + 0.01, min(.pi / 2 - 0.01, elevation))
            cam.roll      = 0
            cam.panOffset = .zero
        }
        persistCamera()
    }

    /// Restores camera from a previously-snapshotted blob (e.g. on profile reconnect).
    /// Silently ignores malformed data.
    public func applyCamera(_ data: Data) {
        guard let cam = try? JSONDecoder().decode(Camera.self, from: data) else { return }
        cameraBox.modify { $0 = cam }
    }

    /// Renders all active topic layers into `view`'s current pass, compositing them
    /// in a single render pass. Render-thread only.
    public func render(view: MTKView, mode: PointColorMode, in cmd: MTLCommandBuffer) {
        guard let passDescriptor = view.currentRenderPassDescriptor,
              let encoder = cmd.makeRenderCommandEncoder(descriptor: passDescriptor)
        else { return }
        render(into: encoder, viewSize: view.drawableSize, mode: mode, cmd: cmd)
        encoder.endEncoding()
    }

    /// Same as `render(view:mode:in:)` but accepts an external encoder so multiple
    /// renderers can share a single render pass. Does NOT endEncoding — the caller
    /// must do that.
    public func render(into encoder: MTLRenderCommandEncoder, viewSize: CGSize, mode: PointColorMode, cmd: MTLCommandBuffer) {
        let frames = frameStore.snapshot().filter { $0.pointCount > 0 }

        let aspect = viewSize.height > 0 ? Float(viewSize.width / viewSize.height) : 1
        let camera = cameraBox.get()
        let vp = camera.viewProjection(aspect: aspect)

        // Draw OccupancyGrid quads before points so point cloud renders on top.
        occupancyGridRenderer?.render(into: encoder, vp: vp)
        // Draw Octomap voxels.
        octomapRenderer?.render(into: encoder, vp: vp)
        // Draw MeshMap triangles.
        meshMapRenderer?.render(into: encoder, vp: vp)

        encoder.setRenderPipelineState(pipeline)
        encoder.setDepthStencilState(depthState)

        guard !frames.isEmpty else { return }

        var uploads: [Upload] = []
        for frame in frames {
            let lod = LODPlan.make(pointCount: frame.pointCount, threshold: lodThreshold)
            guard lod.drawCount > 0 else { continue }
            // Use frame's colorMode for color calculations; fall back to global mode for
            // axis-range and intensity bounds which require the full point set.
            let frameMode = frame.colorMode
            let upload = buildBuffers(frame: frame, lod: lod, mode: frameMode)
            guard let positions = upload.positions else { continue }

            var uniforms = PointUniforms(
                mvp: vp,
                constantColor: frameMode.constantColor,
                axisMin: upload.axisMin,
                axisMax: upload.axisMax,
                intensityMin: frameMode.intensityRange.min,
                intensityMax: frameMode.intensityRange.max,
                colorMode: frameMode.modeIndex,
                axisIndex: frameMode.axisIndex,
                pointSize: frame.pointSize)

            encoder.setVertexBuffer(positions, offset: 0, index: 0)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<PointUniforms>.stride, index: 1)
            encoder.setVertexBuffer(upload.intensities ?? positions, offset: 0, index: 2)
            encoder.setVertexBuffer(upload.colors ?? positions, offset: 0, index: 3)
            encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: lod.drawCount)
            uploads.append(upload)
        }

        // Recycle every layer's buffers once the GPU is done reading them.
        let pool = pool
        let captured = uploads
        cmd.addCompletedHandler { _ in
            for upload in captured {
                if let positions = upload.positions { pool.release(positions) }
                if let intensities = upload.intensities { pool.release(intensities) }
                if let colors = upload.colors { pool.release(colors) }
            }
        }
    }

    /// Returns the current camera's view-projection matrix and eye position.
    /// Used by the coordinator when sharing a render pass with `RobotModelRenderer`.
    public func cameraViewProjection(aspect: Float) -> (viewProjection: simd_float4x4, position: SIMD4<Float>) {
        let cam = cameraBox.get()
        return (cam.viewProjection(aspect: aspect), SIMD4<Float>(cam.position, 1))
    }

    // MARK: - Upload

    private struct Upload: @unchecked Sendable {
        var positions: MTLBuffer?
        var intensities: MTLBuffer?
        var colors: MTLBuffer?
        var axisMin: Float = 0
        var axisMax: Float = 1
    }

    private func buildBuffers(frame: PointCloudFrame, lod: LODPlan, mode: PointColorMode) -> Upload {
        var upload = Upload()
        let n = lod.drawCount
        let posBytes = n * PointCloudFrame.positionStride
        let posBuf = pool.acquireBuffer(length: posBytes, options: .storageModeShared)

        let axisChannel = Int(mode.axisIndex)
        var axisMin = Float.greatestFiniteMagnitude
        var axisMax = -Float.greatestFiniteMagnitude

        frame.positions.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            let src = raw.bindMemory(to: Float.self)
            let dst = posBuf.contents().bindMemory(to: Float.self, capacity: n * 3)
            for i in 0 ..< n {
                let s = (i * lod.stride) * 3
                let x = src[s], y = src[s + 1], z = src[s + 2]
                dst[i * 3] = x
                dst[i * 3 + 1] = y
                dst[i * 3 + 2] = z
                let a = axisChannel == 0 ? x : (axisChannel == 1 ? y : z)
                axisMin = Swift.min(axisMin, a)
                axisMax = Swift.max(axisMax, a)
            }
        }
        upload.positions = posBuf
        upload.axisMin = axisMin
        upload.axisMax = axisMax

        if mode.needsIntensities, let intensities = frame.intensities {
            upload.intensities = decimateScalars(intensities, count: n, stride: lod.stride)
        }
        if mode.needsColors, let colors = frame.colors {
            upload.colors = decimateColors(colors, pointCount: frame.pointCount, count: n, stride: lod.stride)
        }
        return upload
    }

    private func decimateScalars(_ data: Data, count: Int, stride: Int) -> MTLBuffer {
        let buf = pool.acquireBuffer(length: count * 4, options: .storageModeShared)
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            let src = raw.bindMemory(to: Float.self)
            let dst = buf.contents().bindMemory(to: Float.self, capacity: count)
            for i in 0 ..< count {
                dst[i] = src[i * stride]
            }
        }
        return buf
    }

    /// Always uploads float4 colors so the shader has one path; converts RGBA8 if needed.
    private func decimateColors(_ data: Data, pointCount: Int, count: Int, stride: Int) -> MTLBuffer {
        let buf = pool.acquireBuffer(length: count * PointCloudFrame.colorStride, options: .storageModeShared)
        let isFloat4 = data.count == pointCount * PointCloudFrame.colorStride
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            let dst = buf.contents().bindMemory(to: SIMD4<Float>.self, capacity: count)
            if isFloat4 {
                let src = raw.bindMemory(to: SIMD4<Float>.self)
                for i in 0 ..< count {
                    dst[i] = src[i * stride]
                }
            } else {
                let src = raw.bindMemory(to: SIMD4<UInt8>.self)
                for i in 0 ..< count {
                    let c = src[i * stride]
                    dst[i] = SIMD4(Float(c.x), Float(c.y), Float(c.z), Float(c.w)) / 255
                }
            }
        }
        return buf
    }
}
