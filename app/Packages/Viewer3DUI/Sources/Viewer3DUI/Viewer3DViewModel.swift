import CoreGraphics
import Foundation
import ImageIO
import Observation
import simd
import TopicStore
import Transport
import TFTree
import MetalCore
import PointCloudRenderer
import RobotModelRenderer

/// View-model for ``Viewer3DView``.
///
/// Owns the `MetalContext` and both renderer instances. Subscribes to all active
/// `DisplayLayer`s and dispatches each message to the appropriate handler.
/// All handlers push a `PointCloudFrame` into ``PointCloudRenderer``.
@Observable
@MainActor
public final class Viewer3DViewModel {

    // MARK: - Public state

    public private(set) var messageCount: UInt64 = 0
    public private(set) var jointState: JointState = .zero
    public private(set) var isReady: Bool = false
    public private(set) var subscriptionError: String? = nil
    /// Latest decoded images keyed by topic, for Image/CompressedImage overlay.
    public private(set) var latestImages: [String: CGImage] = [:]
    /// True when a RobotModel layer is visible in the active layers list.
    public private(set) var robotModelLayerVisible: Bool = false
    /// Per-layer timestamps of last received message (keyed by layer UUID).
    public private(set) var layerLastReceived: [UUID: Date] = [:]
    /// Per-layer rolling window of receive timestamps for Hz calculation (last 5 seconds).
    public private(set) var layerReceiveTimes: [UUID: [Date]] = [:]
    /// Per-layer subscription start time for "waiting" grace period.
    public private(set) var layerSubscribeTime: [UUID: Date] = [:]
    /// Latest Metal-space positions for each TF frame (used by the frame-label overlay).
    public private(set) var tfFrameWorldPositions: [(id: String, metal: SIMD3<Float>)] = []
    /// All known TF frame names (used by the frame filter in the TF settings popover).
    public private(set) var knownTFFrames: [String] = []
    /// Per-frame axis data for label overlay (origin + axis directions + length).
    public private(set) var tfFrameAxisData: [String: (origin: SIMD3<Float>, xAxis: SIMD3<Float>, yAxis: SIMD3<Float>, zAxis: SIMD3<Float>, length: Float)] = [:]
    /// Chain of frames to highlight in the 3D view (set from TF Tree selection). Nil = no highlighting.
    public var highlightedChain: Set<String>?
    /// Previous staleness status per frame for toast-on-transition detection.
    private var previousStaleStatus: [String: Bool] = [:]

    // MARK: - Metal resources (MainActor-isolated, non-Sendable)

    public private(set) var metalContext: MetalContext?
    public private(set) var pointCloudRenderer: PointCloudRenderer?
    public private(set) var robotRenderer: RobotModelRenderer?

    // MARK: - Private

    private let store: TopicStore
    private let tfTree: TFTree
    private var subscriptionTasks: [Task<Void, Never>] = []
    /// Per-layer position trail for decay-time aware rendering (Odometry, PoseStamped).
    private var layerTrails: [String: [(timestamp: Date, data: Data)]] = [:]
    /// Current active layers (used by TF-frame refresh).
    private var activeLayers: [DisplayLayer] = []
    /// Fixed reference frame all geometry is expressed in (e.g. "map", "odom").
    private var fixedFrame: String = "odom"
    /// The active robot model — set externally when URDF is loaded/received.
    /// Used by subscribeRobotModel to determine the root link for TF tracking.
    public var robotModel: RobotModel?

    public init(store: TopicStore, tfTree: TFTree) {
        self.store = store
        self.tfTree = tfTree
    }

    /// Update the fixed frame used to transform sensor data into world-space.
    /// Call whenever the user changes the fixed-frame picker.
    /// Geometry stays visible during transition; new messages arrive in the new frame.
    public func setFixedFrame(_ frame: String) {
        fixedFrame = frame
    }

    // MARK: - Setup

    func setUp(context: MetalContext, pointCloud: PointCloudRenderer, robot: RobotModelRenderer) {
        self.metalContext = context
        self.pointCloudRenderer = pointCloud
        self.robotRenderer = robot
        self.isReady = true
    }

    func markSetupFailed(error: Error) {
        self.subscriptionError = error.localizedDescription
    }

    public func resetCamera() {
        pointCloudRenderer?.resetCamera()
        robotRenderer?.resetCamera()
    }

    /// Apply a partial camera state update.
    /// Accepts any combination of azimuth, elevation, distance, targetX/Y/Z.
    public func setCamera(params: [String: Double]) {
        pointCloudRenderer?.setCamera(params: params)
    }

    /// Show or hide the reference-plane grid overlay.
    public func setGridVisible(_ visible: Bool) {
        pointCloudRenderer?.setGridVisible(visible)
    }

    // MARK: - Lifecycle

    /// Record that a message was received for the given layer. Updates Hz rolling window.
    @MainActor
    private func recordMessageReceived(layerID: UUID) {
        let now = Date()
        layerLastReceived[layerID] = now
        var times = layerReceiveTimes[layerID] ?? []
        times.append(now)
        // Keep only the last 5-second window
        let cutoff = now.addingTimeInterval(-5.0)
        times.removeAll { $0 < cutoff }
        layerReceiveTimes[layerID] = times
    }

    /// Compute current Hz for a layer from the rolling window.
    public func currentHz(for layerID: UUID) -> Double {
        let times = layerReceiveTimes[layerID] ?? []
        guard times.count >= 2 else { return Double(times.count) / 5.0 }
        return Double(times.count) / 5.0
    }

    /// Layer status for display in the layers panel.
    public enum LayerStatus {
        case live(hz: Double)
        case waiting
        case stale(secondsAgo: Double)
        case noData
        case starting
    }

    public func layerStatus(for layerID: UUID) -> LayerStatus {
        let now = Date()
        let subscribeTime = layerSubscribeTime[layerID] ?? now
        let elapsed = now.timeIntervalSince(subscribeTime)

        guard let last = layerLastReceived[layerID] else {
            if elapsed < 3 { return .starting }
            if elapsed < 30 { return .waiting }
            return .noData
        }

        let age = now.timeIntervalSince(last)
        if age < 5 {
            return .live(hz: currentHz(for: layerID))
        } else if age < 30 {
            return .stale(secondsAgo: age)
        } else {
            return .noData
        }
    }

    public func startSubscriptions(layers: [DisplayLayer]) async {
        // Two call sites request this (initial GPU setup, and layer-list changes) and
        // can race — e.g. on hardware where GPU setup is slow enough that a manual
        // layer edit lands first. If the requested set already matches what's active,
        // this is a redundant call: skip it rather than cancelling and immediately
        // re-creating in-flight subscriptions for the same topics, which can corrupt
        // Swift's task bookkeeping (observed as a swift_task_dealloc crash on Intel).
        guard layers != activeLayers else { return }
        stopSubscriptions()
        pointCloudRenderer?.clearAllLayers()
        activeLayers = layers
        robotModelLayerVisible = layers.contains { $0.type == .robotModel && $0.isVisible }
        applyRobotModelLayerSettings(layers)
        let now = Date()
        for layer in layers where layer.isVisible {
            layerSubscribeTime[layer.id] = now
        }

        for layer in layers where layer.isVisible {
            switch layer.type {
            case .laserScan:       subscribeLaserScan(layer)
            case .pointCloud2:     subscribePointCloud(layer)
            case .occupancyGrid:   subscribeOccupancyGrid(layer)
            case .octomap:         subscribeOctomap(layer)
            case .odometry:        subscribeOdometry(layer)
            case .poseStamped:     subscribePoseStamped(layer)
            case .markerArray:     subscribeMarkerArray(layer)
            case .path:            subscribePath(layer)
            case .image:           subscribeImage(layer)
            case .compressedImage: subscribeCompressedImage(layer)
            case .tfFrames:        subscribeTFFrames(layer)
            case .robotModel:      subscribeRobotModel(layer)
            case .staticMap:
                if let pending = FileLoadRegistry.shared.takeStaticMap(layerID: layer.id) {
                    Task { await self.loadStaticMap(layerID: layer.id, yamlURL: pending.yaml, pgmURL: pending.pgm) }
                }
            case .meshMap:
                if let pending = FileLoadRegistry.shared.takeMeshMap(layerID: layer.id) {
                    Task { await self.loadMeshMap(layerID: layer.id, fileURL: pending) }
                }
            }
        }
    }

    public func stopSubscriptions() {
        subscriptionTasks.forEach { $0.cancel() }
        subscriptionTasks.removeAll()
        layerTrails.removeAll()
        layerLastReceived.removeAll()
        layerReceiveTimes.removeAll()
        layerSubscribeTime.removeAll()
    }

    /// Push robot model layer settings (opacity, tint, hidden links) to the renderer.
    private func applyRobotModelLayerSettings(_ layers: [DisplayLayer]) {
        guard let rmr = robotRenderer,
              let robotLayer = layers.first(where: { $0.type == .robotModel }) else { return }
        let s = robotLayer.settings
        rmr.overrideOpacity = Float(s.opacity)
        rmr.hiddenLinks = s.robotModelHiddenLinks
        rmr.tintColor = SIMD3<Float>(Float(s.robotModelTintR), Float(s.robotModelTintG), Float(s.robotModelTintB))
    }

    /// Update layer display settings without restarting subscriptions.
    /// Call when only color/size/decay changed — topics and visibility are unchanged.
    public func updateLayerSettings(_ newLayers: [DisplayLayer]) {
        activeLayers = newLayers
        robotModelLayerVisible = newLayers.contains { $0.type == .robotModel && $0.isVisible }
        applyRobotModelLayerSettings(newLayers)
    }

    /// Change the topic a layer subscribes to without removing and re-adding it.
    /// Clears the old geometry and restarts all subscriptions with the updated layers array.
    /// The caller is responsible for having already mutated `layers[idx].topic` before calling this.
    public func changeLayerTopic(layerID: UUID, updatedLayers: [DisplayLayer]) {
        // Clear the old geometry for this layer (and any synthetic sub-keys)
        let key = layerID.uuidString
        pointCloudRenderer?.clearTopic(key)
        pointCloudRenderer?.clearTopic(key + "_arrow")
        pointCloudRenderer?.clearTopic(key + "_arrowtip")
        pointCloudRenderer?.clearTopic(key + "_waypoints")
        // Restart all subscriptions with the updated layers array
        Task { await self.startSubscriptions(layers: updatedLayers) }
    }

    // MARK: - LaserScan

    private func subscribeLaserScan(_ layer: DisplayLayer) {
        let layerID = layer.id
        let topic = layer.topic
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let raw = try await store.subscribePayload(topic)
                for await stamped in raw {
                    await self.handleLaserScan(stamped.value, layerID: layerID)
                }
            } catch {
                await MainActor.run { self.subscriptionError = error.localizedDescription }
            }
        }
        subscriptionTasks.append(task)
    }

    private func handleLaserScan(_ data: Data, layerID: UUID) async {
        guard let layer = activeLayers.first(where: { $0.id == layerID }) else { return }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rangesAny = obj["ranges"]          as? [Any],
              let angleMin  = obj["angle_min"]       as? Double,
              let angleInc  = obj["angle_increment"] as? Double,
              let rangeMin  = obj["range_min"]       as? Double,
              let rangeMax  = obj["range_max"]       as? Double
        else { return }

        // --- TF transform: sensor frame → fixed frame ---
        // Parse frame_id and stamp from message header.
        let sensorFrame: String
        var stampNs: UInt64 = UInt64(Date().timeIntervalSince1970 * 1e9)
        if let header = obj["header"] as? [String: Any] {
            sensorFrame = (header["frame_id"] as? String) ?? fixedFrame
            if let stamp = header["stamp"] as? [String: Any] {
                let sec  = (stamp["sec"]  as? UInt64) ?? UInt64((stamp["sec"]  as? Int) ?? 0)
                let nsec = (stamp["nanosec"] as? UInt64) ?? UInt64((stamp["nanosec"] as? Int) ?? 0)
                stampNs = sec * 1_000_000_000 + nsec
            }
        } else {
            sensorFrame = fixedFrame
        }

        // Look up the transform from sensor frame to fixed frame once per message.
        // Returns nil when TF tree has no path — fall back to identity (no transform).
        let tf: TFTransform?
        if sensorFrame == fixedFrame {
            tf = .identity
        } else {
            tf = await tfTree.lookup(from: sensorFrame, to: fixedFrame, at: stampNs)
        }

        let useDistanceColor = layer.settings.colorMode == .byDistance
        let useIntensityColor = layer.settings.colorMode == .byIntensity
        let needPerPointColor = useDistanceColor || useIntensityColor
        // Message hardware range limits
        let msgRangeMin = Float(rangeMin)
        let msgRangeMax = Float(rangeMax)
        // User range filter (applied on top of hardware limits — always active)
        let userRangeMin = Float(layer.settings.rangeMin)
        let userRangeMax = Float(layer.settings.rangeMax)
        let distMin = Float(layer.settings.rangeMin)
        let distMax = Float(max(layer.settings.rangeMax, layer.settings.rangeMin + 0.01))
        let vizMode = layer.settings.scanVizMode
        // Parse intensities if available
        let intensitiesAny = obj["intensities"] as? [Any]
        var intensityMin: Float = 0
        var intensityMax: Float = 1
        if useIntensityColor, let ints = intensitiesAny {
            let validInts = ints.compactMap { $0 as? Double }.filter { $0.isFinite }
            if let mx = validInts.max(), mx > 0 { intensityMax = Float(mx) }
            if let mn = validInts.min() { intensityMin = Float(mn) }
            if intensityMax <= intensityMin { intensityMax = intensityMin + 1 }
        }

        // Rays mode needs 2 points per beam (origin + endpoint)
        let reservedCount = vizMode == .rays ? rangesAny.count * 2 : rangesAny.count
        var positionBytes = Data(capacity: reservedCount * 12)
        var colorBytes: Data? = needPerPointColor ? Data(capacity: reservedCount * 4) : nil
        var count = 0
        for (i, rangeAny) in rangesAny.enumerated() {
            guard let r = rangeAny as? Double else { continue }
            // Hardware limit check (sensor's own constraints)
            guard Float(r) >= msgRangeMin, Float(r) <= msgRangeMax, r.isFinite else { continue }
            // User range filter — removes beams outside the chosen window (e.g. self-reflection)
            guard Float(r) >= userRangeMin, Float(r) <= userRangeMax else { continue }
            let angle = Double(angleMin + Double(i) * angleInc)
            // Compute point in sensor frame (z=0 plane, laser scans in XY).
            let sx = r * cos(angle)
            let sy = r * sin(angle)
            let sz = 0.0

            // Apply TF transform to get world-frame coordinates.
            let (wx, wy, wz): (Float, Float, Float)
            if let t = tf {
                let rotated = t.rotation.act(SIMD3<Double>(sx, sy, sz))
                let world   = rotated + t.translation
                let (mx, my, mz) = swizzle(Float(world.x), Float(world.y), Float(world.z))
                wx = mx; wy = my; wz = mz
            } else {
                let (mx, my, mz) = swizzle(Float(sx), Float(sy), Float(sz))
                wx = mx; wy = my; wz = mz
            }

            // Rays mode: emit sensor origin BEFORE the endpoint so GPU draws origin→endpoint
            if vizMode == .rays {
                // Sensor origin in world Metal space
                let (ox, oy, oz): (Float, Float, Float)
                if let t = tf {
                    let (mx, my, mz) = swizzle(Float(t.translation.x), Float(t.translation.y), Float(t.translation.z))
                    ox = mx; oy = my; oz = mz
                } else {
                    ox = 0; oy = 0; oz = 0
                }
                var ofx = ox, ofy = oy, ofz = oz
                withUnsafeBytes(of: &ofx) { positionBytes.append(contentsOf: $0) }
                withUnsafeBytes(of: &ofy) { positionBytes.append(contentsOf: $0) }
                withUnsafeBytes(of: &ofz) { positionBytes.append(contentsOf: $0) }
                // Use flat layer color for the origin point
                if needPerPointColor {
                    colorBytes?.append(contentsOf: [UInt8(layer.settings.r * 255), UInt8(layer.settings.g * 255), UInt8(layer.settings.b * 255), 255])
                }
                count += 1
            }

            var fx = wx, fy = wy, fz = wz
            withUnsafeBytes(of: &fx) { positionBytes.append(contentsOf: $0) }
            withUnsafeBytes(of: &fy) { positionBytes.append(contentsOf: $0) }
            withUnsafeBytes(of: &fz) { positionBytes.append(contentsOf: $0) }

            if useDistanceColor {
                let t = max(0, min(1, (Float(r) - distMin) / (distMax - distMin)))
                let cr: UInt8
                let cg: UInt8
                let cb: UInt8 = 0
                if t < 0.5 {
                    cr = 255; cg = UInt8(t * 2 * 255)
                } else {
                    cr = UInt8((1 - t) * 2 * 255); cg = 255
                }
                colorBytes?.append(cr)
                colorBytes?.append(cg)
                colorBytes?.append(cb)
                colorBytes?.append(255)
            } else if useIntensityColor {
                let intensity: Float
                if let ints = intensitiesAny, i < ints.count, let val = ints[i] as? Double {
                    intensity = Float(val)
                } else {
                    intensity = 0
                }
                let t = max(0, min(1, (intensity - intensityMin) / (intensityMax - intensityMin)))
                // Blue → Cyan → Green → Yellow → Red (5-stop gradient)
                let cr: UInt8
                let cg: UInt8
                let cb: UInt8
                if t < 0.25 {
                    let s = t / 0.25
                    cr = 0; cg = UInt8(s * 255); cb = 255
                } else if t < 0.5 {
                    let s = (t - 0.25) / 0.25
                    cr = 0; cg = 255; cb = UInt8((1 - s) * 255)
                } else if t < 0.75 {
                    let s = (t - 0.5) / 0.25
                    cr = UInt8(s * 255); cg = 255; cb = 0
                } else {
                    let s = (t - 0.75) / 0.25
                    cr = 255; cg = UInt8((1 - s) * 255); cb = 0
                }
                colorBytes?.append(cr)
                colorBytes?.append(cg)
                colorBytes?.append(cb)
                colorBytes?.append(255)
            }

            count += 1
        }
        guard count > 0 else { return }

        let pointColorMode: PointColorMode = needPerPointColor ? .rgb : colorMode(for: layer.settings)
        let frame = PointCloudFrame(pointCount: count, positions: positionBytes,
                                    intensities: nil, colors: colorBytes,
                                    pointSize: layer.settings.pointSize,
                                    colorMode: pointColorMode)
        await MainActor.run {
            self.pointCloudRenderer?.update(topic: layer.id.uuidString, frame: frame)
            self.messageCount += 1
            self.recordMessageReceived(layerID: layerID)
        }
    }

    // MARK: - PointCloud2

    private func subscribePointCloud(_ layer: DisplayLayer) {
        let layerID = layer.id
        let topic = layer.topic
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let raw = try await store.subscribePayload(topic)
                for await stamped in raw {
                    await self.handlePointCloud(stamped.value, layerID: layerID)
                }
            } catch {
                await MainActor.run { self.subscriptionError = error.localizedDescription }
            }
        }
        subscriptionTasks.append(task)
    }

    private func handlePointCloud(_ data: Data, layerID: UUID) async {
        guard let layer = activeLayers.first(where: { $0.id == layerID }) else { return }
        // Rosbridge sends PointCloud2 as: data=<base64>, fields=[{name,offset,datatype,count}],
        // point_step=<bytes/point>, width=cols, height=rows (1 for unorganized clouds).
        // Old foxglove_bridge path sent points:[[Double]] — that's been removed.
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let base64Str = obj["data"] as? String,
              let rawData = Data(base64Encoded: base64Str, options: .ignoreUnknownCharacters)
        else { return }

        // Bail on big-endian — Mac is little-endian; avoid silent garbage
        if let bigEndian = obj["is_bigendian"] as? Bool, bigEndian { return }

        let width     = obj["width"]      as? Int ?? 0
        let height    = obj["height"]     as? Int ?? 1
        let pointStep = obj["point_step"] as? Int ?? 0
        let totalPoints = width * max(height, 1)
        guard pointStep > 0, totalPoints > 0 else { return }

        // Parse x/y/z and optional intensity/rgb offsets from fields[]
        var xOffset = 0, yOffset = 4, zOffset = 8
        var xType = 7, yType = 7, zType = 7   // 7 = FLOAT32
        var intensityOffset = -1
        var rgbOffset = -1
        if let fields = obj["fields"] as? [[String: Any]] {
            for field in fields {
                guard let name   = field["name"]     as? String,
                      let offset = field["offset"]   as? Int,
                      let dtype  = field["datatype"] as? Int else { continue }
                switch name {
                case "x":         xOffset = offset; xType = dtype
                case "y":         yOffset = offset; yType = dtype
                case "z":         zOffset = offset; zType = dtype
                case "intensity": intensityOffset = offset; _ = dtype
                case "rgb", "rgba": rgbOffset = offset; _ = dtype
                default: break
                }
            }
        }
        // Only FLOAT32 (7) supported for XYZ — FLOAT64 bytes would silently truncate
        guard xType == 7, yType == 7, zType == 7 else { return }

        let pc2Mode = layer.settings.pc2ColorMode
        let pc2HeightMin = Float(layer.settings.pc2HeightMin)
        let pc2HeightMax = Float(max(layer.settings.pc2HeightMax, layer.settings.pc2HeightMin + 0.01))
        let pc2Stride = max(1, layer.settings.pc2StrideN)
        let needPC2Color = pc2Mode != .flat

        let maxOffset = max(xOffset, yOffset, zOffset) + 4
        guard pointStep >= maxOffset else { return }

        var positionBytes = Data(capacity: totalPoints * 12)
        var colorBytes: Data? = needPC2Color ? Data(capacity: totalPoints * 4) : nil
        var count = 0

        // Two-pass for intensity normalization when byIntensity mode
        var intensityMin: Float = 0
        var intensityMax: Float = 1
        if pc2Mode == .byIntensity && intensityOffset >= 0 && pointStep >= intensityOffset + 4 {
            var vals = [Float]()
            vals.reserveCapacity(totalPoints)
            rawData.withUnsafeBytes { ptr in
                for i in stride(from: 0, to: totalPoints, by: pc2Stride) {
                    let base = i * pointStep
                    guard base + intensityOffset + 4 <= ptr.count else { break }
                    let v = ptr.loadUnaligned(fromByteOffset: base + intensityOffset, as: Float.self)
                    if v.isFinite { vals.append(v) }
                }
            }
            if let mn = vals.min() { intensityMin = mn }
            if let mx = vals.max(), mx > intensityMin { intensityMax = mx }
        }

        rawData.withUnsafeBytes { ptr in
            for i in 0..<totalPoints {
                // Apply stride — skip non-sampled points
                if pc2Stride > 1 && i % pc2Stride != 0 { continue }
                let base = i * pointStep
                guard base + maxOffset <= ptr.count else { break }
                let x = ptr.loadUnaligned(fromByteOffset: base + xOffset, as: Float.self)
                let y = ptr.loadUnaligned(fromByteOffset: base + yOffset, as: Float.self)
                let z = ptr.loadUnaligned(fromByteOffset: base + zOffset, as: Float.self)
                // Skip NaN/Inf (always invalid)
                guard x.isFinite, y.isFinite, z.isFinite else { continue }
                // Skip zero points — synthetic depth publisher emits (0,0,0) for invalid pixels
                guard x != 0 || y != 0 || z != 0 else { continue }
                let (sx, sy, sz) = swizzle(x, y, z)
                var fx = sx, fy = sy, fz = sz
                withUnsafeBytes(of: &fx) { positionBytes.append(contentsOf: $0) }
                withUnsafeBytes(of: &fy) { positionBytes.append(contentsOf: $0) }
                withUnsafeBytes(of: &fz) { positionBytes.append(contentsOf: $0) }

                // Per-point color for non-flat modes
                if needPC2Color {
                    switch pc2Mode {
                    case .byHeight:
                        // Metal Y-axis = ROS Z = height
                        let t = max(0, min(1, (sy - pc2HeightMin) / (pc2HeightMax - pc2HeightMin)))
                        let cr, cg, cb: UInt8
                        if t < 0.25 {
                            let s = t / 0.25
                            cr = 0; cg = UInt8(s * 255); cb = 255        // blue→cyan
                        } else if t < 0.5 {
                            let s = (t - 0.25) / 0.25
                            cr = 0; cg = 255; cb = UInt8((1 - s) * 255)  // cyan→green
                        } else if t < 0.75 {
                            let s = (t - 0.5) / 0.25
                            cr = UInt8(s * 255); cg = 255; cb = 0        // green→yellow
                        } else {
                            let s = (t - 0.75) / 0.25
                            cr = 255; cg = UInt8((1 - s) * 255); cb = 0  // yellow→red
                        }
                        colorBytes?.append(contentsOf: [cr, cg, cb, 255])
                    case .byIntensity:
                        var intensity: Float = 0
                        if intensityOffset >= 0 && base + intensityOffset + 4 <= ptr.count {
                            intensity = ptr.loadUnaligned(fromByteOffset: base + intensityOffset, as: Float.self)
                        }
                        let t = intensityMax > intensityMin
                            ? max(0, min(1, (intensity - intensityMin) / (intensityMax - intensityMin)))
                            : 0
                        let v = UInt8(t * 255)
                        colorBytes?.append(contentsOf: [v, v, v, 255])
                    case .byRGB:
                        if rgbOffset >= 0 && base + rgbOffset + 4 <= ptr.count {
                            let packed = ptr.loadUnaligned(fromByteOffset: base + rgbOffset, as: UInt32.self)
                            let pr = UInt8((packed >> 16) & 0xFF)
                            let pg = UInt8((packed >>  8) & 0xFF)
                            let pb = UInt8( packed        & 0xFF)
                            colorBytes?.append(contentsOf: [pr, pg, pb, 255])
                        } else {
                            colorBytes?.append(contentsOf: [200, 200, 200, 255])
                        }
                    case .flat:
                        colorBytes?.append(contentsOf: [200, 200, 200, 255])
                    }
                }

                count += 1
            }
        }
        guard count > 0 else { return }

        let pc2ColorMode2: PointColorMode = needPC2Color ? .rgb : colorMode(for: layer.settings)
        let frame = PointCloudFrame(pointCount: count, positions: positionBytes,
                                    intensities: nil, colors: colorBytes,
                                    pointSize: layer.settings.pointSize,
                                    colorMode: pc2ColorMode2)
        await MainActor.run {
            self.pointCloudRenderer?.update(topic: layer.id.uuidString, frame: frame)
            self.messageCount += 1
            self.recordMessageReceived(layerID: layerID)
        }
    }

    // MARK: - OccupancyGrid

    private func subscribeOccupancyGrid(_ layer: DisplayLayer) {
        let layerID = layer.id
        let topic = layer.topic
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let raw = try await store.subscribePayload(topic)
                for await stamped in raw {
                    await self.handleOccupancyGrid(stamped.value, layerID: layerID)
                }
            } catch {
                await MainActor.run { self.subscriptionError = error.localizedDescription }
            }
        }
        subscriptionTasks.append(task)
    }

    /// Decodes an OccupancyGrid message and uploads it as a quad mesh.
    ///
    /// Cells are rendered as filled world-space quads (one quad per cell):
    /// - cell == -1 / 255 (unknown): skipped — not rendered
    /// - cell == 0  (free):    near-white (240, 240, 240)
    /// - cell 1–100 (occupied): near-black, scaled by value (darker = more occupied)
    private func handleOccupancyGrid(_ data: Data, layerID: UUID) async {
        guard activeLayers.first(where: { $0.id == layerID }) != nil else { return }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let info = obj["info"] as? [String: Any],
              let width = info["width"] as? Int,
              let resolution = info["resolution"] as? Double,
              resolution > 0, width > 0
        else { return }

        let dataArr: [Int]
        if let intArr = obj["data"] as? [Int] {
            dataArr = intArr
        } else if let b64 = obj["data"] as? String,
                  let bytes = Data(base64Encoded: b64, options: .ignoreUnknownCharacters) {
            dataArr = bytes.map { Int(Int8(bitPattern: $0)) }
        } else {
            return
        }

        guard dataArr.count <= 1_000_000 else { return }

        // Parse header frame_id and stamp (same pattern as handleLaserScan).
        let headerFrame: String
        var stampNs: UInt64 = UInt64(Date().timeIntervalSince1970 * 1e9)
        if let header = obj["header"] as? [String: Any] {
            headerFrame = (header["frame_id"] as? String) ?? fixedFrame
            if let stamp = header["stamp"] as? [String: Any] {
                let sec  = (stamp["sec"]  as? UInt64) ?? UInt64((stamp["sec"]  as? Int) ?? 0)
                let nsec = (stamp["nanosec"] as? UInt64) ?? UInt64((stamp["nanosec"] as? Int) ?? 0)
                stampNs = sec * 1_000_000_000 + nsec
            }
        } else {
            headerFrame = fixedFrame
        }

        let originDict = info["origin"] as? [String: Any]
        let pos = originDict.flatMap { $0["position"] as? [String: Any] }
        let originRosX = (pos?["x"] as? Double) ?? 0.0
        let originRosY = (pos?["y"] as? Double) ?? 0.0

        // Parse map-origin quaternion in ROS frame (identity for most SLAM maps).
        let originQuatRos: simd_quatd
        if let ori = originDict.flatMap({ $0["orientation"] as? [String: Any] }),
           let qx = ori["x"] as? Double, let qy = ori["y"] as? Double,
           let qz = ori["z"] as? Double, let qw = ori["w"] as? Double {
            originQuatRos = simd_quatd(ix: qx, iy: qy, iz: qz, r: qw)
        } else {
            originQuatRos = simd_quatd(ix: 0, iy: 0, iz: 0, r: 1)
        }

        // Apply TF transform from map's header frame to the fixed frame (in ROS space).
        // If same frame, skip lookup. If lookup fails, fall back to identity (render at info.origin).
        let finalOriginX: Float
        let finalOriginY: Float
        let finalOriginRotation: simd_quatf

        if headerFrame == fixedFrame {
            finalOriginX = Float(originRosX)
            finalOriginY = Float(originRosY)
            finalOriginRotation = simd_quatf(ix: Float(originQuatRos.imag.x),
                                             iy: Float(originQuatRos.imag.y),
                                             iz: Float(originQuatRos.imag.z),
                                             r:  Float(originQuatRos.real))
        } else {
            let tf = await tfTree.lookup(from: headerFrame, to: fixedFrame, at: stampNs)
            if let tf {
                // Compose: world position = tf.rotation.act(originRos) + tf.translation
                let pWorld = tf.rotation.act(SIMD3<Double>(originRosX, originRosY, 0)) + tf.translation
                // Compose: world rotation = tf.rotation * originQuat (ROS quaternion multiplication)
                let qWorld = tf.rotation * originQuatRos
                finalOriginX = Float(pWorld.x)
                finalOriginY = Float(pWorld.y)
                finalOriginRotation = simd_quatf(ix: Float(qWorld.imag.x),
                                                 iy: Float(qWorld.imag.y),
                                                 iz: Float(qWorld.imag.z),
                                                 r:  Float(qWorld.real))
            } else {
                finalOriginX = Float(originRosX)
                finalOriginY = Float(originRosY)
                finalOriginRotation = simd_quatf(ix: Float(originQuatRos.imag.x),
                                                 iy: Float(originQuatRos.imag.y),
                                                 iz: Float(originQuatRos.imag.z),
                                                 r:  Float(originQuatRos.real))
            }
        }

        let topicKey = layerID.uuidString
        let res = Float(resolution)

        let tint: SIMD4<Float>
        let freeColor: SIMD3<Float>
        let unknownColor: SIMD3<Float>
        let showGridLines: Bool
        let showUnknownCells: Bool
        if let l = activeLayers.first(where: { $0.id == layerID }) {
            tint = SIMD4<Float>(Float(l.settings.r), Float(l.settings.g), Float(l.settings.b), Float(l.settings.opacity))
            freeColor = SIMD3<Float>(Float(l.settings.freeR), Float(l.settings.freeG), Float(l.settings.freeB))
            unknownColor = SIMD3<Float>(Float(l.settings.unknownR), Float(l.settings.unknownG), Float(l.settings.unknownB))
            showGridLines = l.settings.showGridLines
            showUnknownCells = l.settings.showUnknownCells
        } else {
            tint = SIMD4<Float>(1, 1, 1, 1)
            freeColor = SIMD3<Float>(0.94, 0.94, 0.94)
            unknownColor = SIMD3<Float>(0.55, 0.65, 0.75)
            showGridLines = false
            showUnknownCells = true
        }

        // Warn if map is very large
        if dataArr.count > 1_000_000 {
            await MainActor.run {
                NotificationCenter.default.post(
                    name: .mapTooLarge,
                    object: dataArr.count)
            }
        }

        await MainActor.run {
            self.pointCloudRenderer?.updateOccupancyGrid(
                topic: topicKey,
                cells: dataArr,
                width: width,
                resolution: res,
                originX: finalOriginX,
                originY: finalOriginY,
                originRotation: finalOriginRotation,
                tintColor: tint,
                freeColor: freeColor,
                unknownColor: unknownColor,
                showGridLines: showGridLines,
                showUnknownCells: showUnknownCells)
            self.messageCount += 1
            self.recordMessageReceived(layerID: layerID)
        }
    }

    // MARK: - Octomap

    private func subscribeOctomap(_ layer: DisplayLayer) {
        let layerID = layer.id
        let topic = layer.topic
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let raw = try await store.subscribePayload(topic)
                for await stamped in raw {
                    await self.handleOctomap(stamped.value, layerID: layerID)
                }
            } catch {
                await MainActor.run { self.subscriptionError = error.localizedDescription }
            }
        }
        subscriptionTasks.append(task)
    }

    /// Decodes an Octomap message and renders voxels.
    private func handleOctomap(_ data: Data, layerID: UUID) async {
        guard activeLayers.first(where: { $0.id == layerID }) != nil else { return }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        // Parse header for frame_id and stamp
        let headerFrame: String
        var stampNs: UInt64 = UInt64(Date().timeIntervalSince1970 * 1e9)
        if let header = obj["header"] as? [String: Any] {
            headerFrame = (header["frame_id"] as? String) ?? fixedFrame
            if let stamp = header["stamp"] as? [String: Any] {
                let sec  = (stamp["sec"]  as? UInt64) ?? UInt64((stamp["sec"]  as? Int) ?? 0)
                let nsec = (stamp["nanosec"] as? UInt64) ?? UInt64((stamp["nanosec"] as? Int) ?? 0)
                stampNs = sec * 1_000_000_000 + nsec
            }
        } else {
            headerFrame = fixedFrame
        }

        // Get binary data
        guard let binaryData = obj["data"] as? String,
              let rawData = Data(base64Encoded: binaryData, options: .ignoreUnknownCharacters) else {
            return
        }

        // Get resolution
        let resolution = (obj["resolution"] as? Double) ?? 0.05

        // Look up TF transform from header frame to fixed frame
        let tf = headerFrame == fixedFrame ? TFTransform.identity : await tfTree.lookup(from: headerFrame, to: fixedFrame, at: stampNs)

        // Parse octree nodes from binary data
        // Simplified: extract leaf nodes with position and occupied status
        let voxels = parseOctomapBinary(rawData, resolution: Float(resolution), tf: tf)

        // Get settings from active layer
        let showOccupied: Bool
        let showFree: Bool
        let showUnknown: Bool
        let occupiedColor: SIMD4<Float>
        let freeColor: SIMD4<Float>
        let alpha: Double
        let strideN: Int

        if let l = activeLayers.first(where: { $0.id == layerID }) {
            showOccupied = l.settings.octomapShowOccupied
            showFree = l.settings.octomapShowFree
            showUnknown = l.settings.octomapShowUnknown
            occupiedColor = SIMD4<Float>(Float(l.settings.octomapOccupiedR), Float(l.settings.octomapOccupiedG), Float(l.settings.octomapOccupiedB), 1.0)
            freeColor = SIMD4<Float>(Float(l.settings.octomapFreeR), Float(l.settings.octomapFreeG), Float(l.settings.octomapFreeB), 1.0)
            alpha = l.settings.octomapAlpha
            strideN = l.settings.octomapStrideN
        } else {
            showOccupied = true; showFree = false; showUnknown = false
            occupiedColor = SIMD4<Float>(0.2, 0.6, 0.8, 1.0)
            freeColor = SIMD4<Float>(0.8, 0.9, 1.0, 1.0)
            alpha = 0.7; strideN = 1
        }

        let topicKey = layerID.uuidString
        await MainActor.run {
            self.pointCloudRenderer?.updateOctomap(
                topic: topicKey,
                voxels: voxels,
                showOccupied: showOccupied,
                showFree: showFree,
                showUnknown: showUnknown,
                occupiedColor: occupiedColor,
                freeColor: freeColor,
                alpha: alpha,
                strideN: strideN)
            self.messageCount += 1
            self.recordMessageReceived(layerID: layerID)
        }
    }

    /// Parse binary octomap data into voxel positions.
    /// This is a simplified parser that extracts leaf nodes.
    private func parseOctomapBinary(_ data: Data, resolution: Float, tf: TFTransform?) -> [(x: Float, y: Float, z: Float, size: Float, occupied: Bool)] {
        var voxels: [(x: Float, y: Float, z: Float, size: Float, occupied: Bool)] = []

        // Binary octomap format: iterate through nodes
        // Each node has: child existence mask (1 byte) + occupancy byte
        // Leaf nodes are at depth where all children are pruned
        var offset = 0
        let size = data.count

        func parseNode(depth: Int, originX: Float, originY: Float, originZ: Float) {
            guard offset + 2 <= size else { return }

            let childMask = data[offset]
            offset += 1
            let occupancy = data[offset]
            offset += 1

            let nodeSize = resolution * pow(2.0, Float(depth))
            let childSize = nodeSize * 0.5

            // Check if this is a leaf node (no children)
            if childMask == 0 {
                let isOccupied = occupancy > 127
                var px = originX
                var py = originY
                var pz = originZ

                // Apply TF transform if available
                if let tf {
                    let rosPos = SIMD3<Double>(Double(px), Double(py), Double(pz))
                    let metalPos = tf.rotation.act(rosPos) + tf.translation
                    px = Float(metalPos.x)
                    py = Float(metalPos.y)
                    pz = Float(metalPos.z)
                }

                let (mx, my, mz) = swizzle(px, py, pz)

                voxels.append((x: mx, y: my, z: mz, size: nodeSize, occupied: isOccupied))
                return
            }

            // Parse children
            for i in 0..<8 {
                guard (childMask & (1 << i)) != 0 else { continue }
                let ox = originX + ((i & 1) != 0 ? childSize : 0)
                let oy = originY + ((i & 2) != 0 ? childSize : 0)
                let oz = originZ + ((i & 4) != 0 ? childSize : 0)
                parseNode(depth: depth + 1, originX: ox, originY: oy, originZ: oz)
            }
        }

        // Start parsing from root
        parseNode(depth: 0, originX: 0, originY: 0, originZ: 0)

        return voxels
    }

    // MARK: - Static Map Loading

    /// Load a static map from .yaml + .pgm file pair.
    public func loadStaticMap(layerID: UUID, yamlURL: URL, pgmURL: URL) async {
        guard activeLayers.contains(where: { $0.id == layerID }) else { return }

        do {
            let yamlData = try Data(contentsOf: yamlURL)
            let pgmData = try Data(contentsOf: pgmURL)
            let map = try StaticMapParser.parse(yamlData: yamlData, pgmData: pgmData)

            let topicKey = layerID.uuidString
            let res = Float(map.resolution)

            // Get settings
            let tint: SIMD4<Float>
            let freeColor: SIMD3<Float>
            let unknownColor: SIMD3<Float>
            let showGridLines: Bool
            let showUnknownCells: Bool

            if let l = activeLayers.first(where: { $0.id == layerID }) {
                tint = SIMD4<Float>(Float(l.settings.r), Float(l.settings.g), Float(l.settings.b), Float(l.settings.opacity))
                freeColor = SIMD3<Float>(Float(l.settings.freeR), Float(l.settings.freeG), Float(l.settings.freeB))
                unknownColor = SIMD3<Float>(Float(l.settings.unknownR), Float(l.settings.unknownG), Float(l.settings.unknownB))
                showGridLines = l.settings.showGridLines
                showUnknownCells = l.settings.showUnknownCells
            } else {
                tint = SIMD4<Float>(1, 1, 1, 1)
                freeColor = SIMD3<Float>(0.94, 0.94, 0.94)
                unknownColor = SIMD3<Float>(0.55, 0.65, 0.75)
                showGridLines = false
                showUnknownCells = true
            }

            await MainActor.run {
                self.pointCloudRenderer?.updateOccupancyGrid(
                    topic: topicKey,
                    cells: map.cells,
                    width: map.width,
                    resolution: res,
                    originX: Float(map.originX),
                    originY: Float(map.originY),
                    originRotation: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1),
                    tintColor: tint,
                    freeColor: freeColor,
                    unknownColor: unknownColor,
                    showGridLines: showGridLines,
                    showUnknownCells: showUnknownCells)
                self.messageCount += 1
                self.recordMessageReceived(layerID: layerID)
            }
        } catch {
            await MainActor.run { self.subscriptionError = "Failed to load map: \(error.localizedDescription)" }
        }
    }

    // MARK: - Mesh Map Loading

    /// Load a mesh map from PLY or OBJ file.
    public func loadMeshMap(layerID: UUID, fileURL: URL) async {
        guard activeLayers.contains(where: { $0.id == layerID }) else { return }

        do {
            let data = try Data(contentsOf: fileURL)
            let mesh: PLYParser.ParsedMesh

            if fileURL.pathExtension.lowercased() == "ply" {
                mesh = try PLYParser.parse(data: data)
            } else if fileURL.pathExtension.lowercased() == "obj" {
                mesh = try OBJParser.parse(data: data)
            } else {
                throw MapParseError.fileNotFound("Unsupported format: \(fileURL.pathExtension)")
            }

            let tintColor: SIMD4<Float>
            let strideN: Int
            if let l = activeLayers.first(where: { $0.id == layerID }) {
                tintColor = SIMD4<Float>(Float(l.settings.meshMapR), Float(l.settings.meshMapG), Float(l.settings.meshMapB), 1.0)
                strideN = l.settings.meshMapStrideN
            } else {
                tintColor = SIMD4<Float>(0.9, 0.9, 0.9, 1.0)
                strideN = 1
            }

            let topicKey = layerID.uuidString
            await MainActor.run {
                self.pointCloudRenderer?.updateMeshMap(
                    topic: topicKey,
                    vertices: mesh.vertices,
                    indices: mesh.indices,
                    tintColor: tintColor,
                    strideN: strideN)
                self.messageCount += 1
                self.recordMessageReceived(layerID: layerID)
                self.resetCamera()
            }
        } catch {
            await MainActor.run { self.subscriptionError = "Failed to load mesh: \(error.localizedDescription)" }
        }
    }

    // MARK: - Odometry

    private func subscribeOdometry(_ layer: DisplayLayer) {
        let layerID = layer.id
        let topic = layer.topic
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let raw = try await store.subscribePayload(topic)
                for await stamped in raw {
                    await self.handleOdometry(stamped.value, layerID: layerID)
                }
            } catch {
                await MainActor.run { self.subscriptionError = error.localizedDescription }
            }
        }
        subscriptionTasks.append(task)
    }

    private func handleOdometry(_ data: Data, layerID: UUID) async {
        guard let layer = activeLayers.first(where: { $0.id == layerID }) else { return }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pose = obj["pose"] as? [String: Any],
              let innerPose = pose["pose"] as? [String: Any],
              let pos = innerPose["position"] as? [String: Any],
              let x = pos["x"] as? Double,
              let y = pos["y"] as? Double,
              let z = pos["z"] as? Double
        else { return }

        let (mx, my, mz) = swizzle(Float(x), Float(y), Float(z))
        let point = Data(floats: [mx, my, mz])

        if layer.settings.showOdomTrail {
            await pushTrailPoint(point, layerID: layerID, trailLength: layer.settings.odomTrailLength)
        }
    }

    // MARK: - PoseStamped

    private func subscribePoseStamped(_ layer: DisplayLayer) {
        let layerID = layer.id
        let topic = layer.topic
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let raw = try await store.subscribePayload(topic)
                for await stamped in raw {
                    await self.handlePoseStamped(stamped.value, layerID: layerID)
                }
            } catch {
                await MainActor.run { self.subscriptionError = error.localizedDescription }
            }
        }
        subscriptionTasks.append(task)
    }

    private func handlePoseStamped(_ data: Data, layerID: UUID) async {
        guard let layer = activeLayers.first(where: { $0.id == layerID }) else { return }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pose = obj["pose"] as? [String: Any],
              let pos = pose["position"] as? [String: Any],
              let x = pos["x"] as? Double,
              let y = pos["y"] as? Double,
              let z = pos["z"] as? Double
        else { return }

        let (mx, my, mz) = swizzle(Float(x), Float(y), Float(z))

        var yaw: Double = 0
        if let ori = pose["orientation"] as? [String: Any],
           let qx = ori["x"] as? Double, let qy = ori["y"] as? Double,
           let qz = ori["z"] as? Double, let qw = ori["w"] as? Double {
            yaw = rosYaw(from: (qx, qy, qz, qw))
        }

        // Build directional arrow: forward direction in ROS XY plane
        // ROS forward = (cos(yaw), sin(yaw), 0) → swizzle → Metal forward
        let rosForwardX = Float(cos(yaw))
        let rosForwardY = Float(sin(yaw))
        let (fwdX, _, fwdZ) = swizzle(rosForwardX, rosForwardY, 0)
        let forward = SIMD3<Float>(fwdX, 0, fwdZ)  // keep Y=0 (ground plane arrow)

        // Shaft: 10 points from origin along forward direction
        let shaftSteps = 10
        let shaftLength: Float = 0.5  // 0.5m shaft
        var positionBytes = Data(capacity: (shaftSteps + 1) * 12)
        var colorBytes = Data(capacity: (shaftSteps + 1) * 4)

        let cr = UInt8(layer.settings.r * 255)
        let cg = UInt8(layer.settings.g * 255)
        let cb = UInt8(layer.settings.b * 255)

        for step in 0..<shaftSteps {
            let frac = Float(step) / Float(shaftSteps - 1)
            let p = SIMD3<Float>(mx, my, mz) + forward * (frac * shaftLength)
            var px = p.x, py = p.y, pz = p.z
            withUnsafeBytes(of: &px) { positionBytes.append(contentsOf: $0) }
            withUnsafeBytes(of: &py) { positionBytes.append(contentsOf: $0) }
            withUnsafeBytes(of: &pz) { positionBytes.append(contentsOf: $0) }
            colorBytes.append(contentsOf: [cr, cg, cb, 255])
        }

        let arrowKey = layerID.uuidString + "_arrow"
        let shaftCount = shaftSteps
        let shaftFrame = PointCloudFrame(pointCount: shaftCount, positions: positionBytes,
                                         intensities: nil, colors: colorBytes,
                                         pointSize: layer.settings.pointSize,
                                         colorMode: .rgb)

        // Tip: 1 large point at shaft end
        let tip = SIMD3<Float>(mx, my, mz) + forward * shaftLength
        var tipPos = Data(capacity: 12)
        var tx = tip.x, ty = tip.y, tz = tip.z
        withUnsafeBytes(of: &tx) { tipPos.append(contentsOf: $0) }
        withUnsafeBytes(of: &ty) { tipPos.append(contentsOf: $0) }
        withUnsafeBytes(of: &tz) { tipPos.append(contentsOf: $0) }
        let tipColor = Data([cr, cg, cb, 255])
        let tipFrame = PointCloudFrame(pointCount: 1, positions: tipPos,
                                       intensities: nil, colors: tipColor,
                                       pointSize: layer.settings.pointSize * 3,
                                       colorMode: .rgb)
        let tipKey = layerID.uuidString + "_arrowtip"

        await MainActor.run {
            self.pointCloudRenderer?.update(topic: arrowKey, frame: shaftFrame)
            self.pointCloudRenderer?.update(topic: tipKey, frame: tipFrame)
            self.messageCount += 1
            self.recordMessageReceived(layerID: layerID)
        }
    }

    // MARK: - MarkerArray

    private func subscribeMarkerArray(_ layer: DisplayLayer) {
        let layerID = layer.id
        let topic = layer.topic
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let raw = try await store.subscribePayload(topic)
                for await stamped in raw {
                    await self.handleMarkerArray(stamped.value, layerID: layerID)
                }
            } catch {
                await MainActor.run { self.subscriptionError = error.localizedDescription }
            }
        }
        subscriptionTasks.append(task)
    }

    /// Flattens all markers into a single point cloud. Supports POINTS (8), SPHERE_LIST (7),
    /// CUBE_LIST (6), LINE_STRIP (4), LINE_LIST (5), ARROW (0), SPHERE (2), CUBE (1).
    private func handleMarkerArray(_ data: Data, layerID: UUID) async {
        guard let layer = activeLayers.first(where: { $0.id == layerID }) else { return }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let markers = obj["markers"] as? [[String: Any]]
        else { return }

        var positionBytes = Data()
        var count = 0

        let nsFilter = layer.settings.markerNamespaceFilter
        for marker in markers {
            // Skip DELETE markers (action == 2 or 3)
            if let action = marker["action"] as? Int, action >= 2 { continue }
            guard let markerType = marker["type"] as? Int else { continue }
            // Namespace filter — skip markers whose ns doesn't contain the filter string
            if !nsFilter.isEmpty {
                let ns = marker["ns"] as? String ?? ""
                guard ns.localizedCaseInsensitiveContains(nsFilter) else { continue }
            }

            // Extract position points depending on marker type
            if let points = marker["points"] as? [[String: Any]], !points.isEmpty {
                // POINTS(8), SPHERE_LIST(7), CUBE_LIST(6), LINE_STRIP(4), LINE_LIST(5)
                for p in points {
                    if let x = p["x"] as? Double, let y = p["y"] as? Double, let z = p["z"] as? Double {
                        let (fx, fy, fz) = swizzle(Float(x), Float(y), Float(z))
                        var vx = fx, vy = fy, vz = fz
                        withUnsafeBytes(of: &vx) { positionBytes.append(contentsOf: $0) }
                        withUnsafeBytes(of: &vy) { positionBytes.append(contentsOf: $0) }
                        withUnsafeBytes(of: &vz) { positionBytes.append(contentsOf: $0) }
                        count += 1
                    }
                }
            } else if let pose = marker["pose"] as? [String: Any],
                      let pos = pose["position"] as? [String: Any],
                      let x = pos["x"] as? Double, let y = pos["y"] as? Double, let z = pos["z"] as? Double {
                // ARROW(0), CUBE(1), SPHERE(2), CYLINDER(3), TEXT(9)
                _ = markerType  // acknowledged; all single-pose types rendered at position
                let (fx, fy, fz) = swizzle(Float(x), Float(y), Float(z))
                var vx = fx, vy = fy, vz = fz
                withUnsafeBytes(of: &vx) { positionBytes.append(contentsOf: $0) }
                withUnsafeBytes(of: &vy) { positionBytes.append(contentsOf: $0) }
                withUnsafeBytes(of: &vz) { positionBytes.append(contentsOf: $0) }
                count += 1
            }
        }
        guard count > 0 else { return }

        let frame = PointCloudFrame(pointCount: count, positions: positionBytes,
                                    intensities: nil, colors: nil,
                                    pointSize: layer.settings.pointSize,
                                    colorMode: colorMode(for: layer.settings))
        await MainActor.run {
            self.pointCloudRenderer?.update(topic: layer.id.uuidString, frame: frame)
            self.messageCount += 1
            self.recordMessageReceived(layerID: layerID)
        }
    }

    // MARK: - Nav Path (nav_msgs/msg/Path)

    private func subscribePath(_ layer: DisplayLayer) {
        let layerID = layer.id
        let topic = layer.topic
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let raw = try await store.subscribePayload(topic)
                for await stamped in raw {
                    await self.handlePath(stamped.value, layerID: layerID)
                }
            } catch {
                await MainActor.run { self.subscriptionError = error.localizedDescription }
            }
        }
        subscriptionTasks.append(task)
    }

    /// Converts a nav_msgs/msg/Path to a dense point strip, rendered as a coloured
    /// line on the ground plane. Points are sampled every pose.
    private func handlePath(_ data: Data, layerID: UUID) async {
        guard let layer = activeLayers.first(where: { $0.id == layerID }) else { return }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let poses = obj["poses"] as? [[String: Any]], !poses.isEmpty
        else { return }

        var positionBytes = Data(capacity: poses.count * 12)
        var waypointBytes = Data(capacity: poses.count * 12)
        var count = 0
        var waypointCount = 0

        let showWaypoints = layer.settings.showPathWaypoints
        let waypointEveryN = max(1, layer.settings.pathWaypointEveryN)
        let waypointSize = Float(layer.settings.pathWaypointSize)

        for (poseIdx, poseStamped) in poses.enumerated() {
            guard let pose = poseStamped["pose"] as? [String: Any],
                  let pos = pose["position"] as? [String: Any],
                  let x = pos["x"] as? Double,
                  let y = pos["y"] as? Double,
                  let z = pos["z"] as? Double
            else { continue }
            let (fx, fy, fz) = swizzle(Float(x), Float(y), Float(z))
            var vx = fx, vy = fy, vz = fz
            withUnsafeBytes(of: &vx) { positionBytes.append(contentsOf: $0) }
            withUnsafeBytes(of: &vy) { positionBytes.append(contentsOf: $0) }
            withUnsafeBytes(of: &vz) { positionBytes.append(contentsOf: $0) }
            count += 1

            // Waypoint every N poses
            if showWaypoints && poseIdx % waypointEveryN == 0 {
                withUnsafeBytes(of: &vx) { waypointBytes.append(contentsOf: $0) }
                withUnsafeBytes(of: &vy) { waypointBytes.append(contentsOf: $0) }
                withUnsafeBytes(of: &vz) { waypointBytes.append(contentsOf: $0) }
                waypointCount += 1
            }
        }
        guard count > 0 else { return }

        let frame = PointCloudFrame(pointCount: count, positions: positionBytes,
                                    intensities: nil, colors: nil,
                                    pointSize: layer.settings.pointSize,
                                    colorMode: colorMode(for: layer.settings))
        let waypointKey = layerID.uuidString + "_waypoints"
        let pathFrame: PointCloudFrame? = waypointCount > 0 ? PointCloudFrame(
            pointCount: waypointCount, positions: waypointBytes,
            intensities: nil, colors: nil,
            pointSize: waypointSize,
            colorMode: colorMode(for: layer.settings)) : nil

        await MainActor.run {
            self.pointCloudRenderer?.update(topic: layer.id.uuidString, frame: frame)
            if let wf = pathFrame {
                self.pointCloudRenderer?.update(topic: waypointKey, frame: wf)
            } else {
                self.pointCloudRenderer?.clearTopic(waypointKey)
            }
            self.messageCount += 1
            self.recordMessageReceived(layerID: layerID)
        }
    }

    // MARK: - Image / CompressedImage

    private func subscribeImage(_ layer: DisplayLayer) {
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let raw = try await store.subscribePayload(layer.topic)
                for await stamped in raw {
                    await self.handleImage(stamped.value, topic: layer.topic)
                }
            } catch { }
        }
        subscriptionTasks.append(task)
    }

    private func subscribeCompressedImage(_ layer: DisplayLayer) {
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let raw = try await store.subscribePayload(layer.topic)
                for await stamped in raw {
                    await self.handleCompressedImage(stamped.value, topic: layer.topic)
                }
            } catch { }
        }
        subscriptionTasks.append(task)
    }

    private func handleImage(_ data: Data, topic: String) async {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let height = obj["height"] as? Int,
              let width  = obj["width"]  as? Int,
              let rawData = obj["data"]  as? String,
              let imageData = Data(base64Encoded: rawData, options: .ignoreUnknownCharacters),
              let provider = CGDataProvider(data: imageData as CFData)
        else { return }

        // Assume bgr8 encoding (3 bytes per pixel)
        let image = CGImage(width: width, height: height,
                            bitsPerComponent: 8, bitsPerPixel: 24,
                            bytesPerRow: width * 3,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                            provider: provider,
                            decode: nil, shouldInterpolate: true,
                            intent: .defaultIntent)
        await MainActor.run {
            if let image { self.latestImages[topic] = image }
            self.messageCount += 1
        }
    }

    private func handleCompressedImage(_ data: Data, topic: String) async {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawData = obj["data"] as? String,
              let imageData = Data(base64Encoded: rawData, options: .ignoreUnknownCharacters),
              let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return }
        await MainActor.run {
            self.latestImages[topic] = image
            self.messageCount += 1
        }
    }

    // MARK: - Robot Model

    /// Subscribes to /joint_states so the robot model updates pose in real time.
    /// The visual rendering is handled by RobotModelMetalView driven by `robotModelLayerVisible`.
    private func subscribeRobotModel(_ layer: DisplayLayer) {
        // Joint state subscription
        let jointTask = Task { [weak self] in
            guard let self else { return }
            do {
                let raw = try await store.subscribePayload("/joint_states")
                for await stamped in raw {
                    await self.handleJointStates(stamped.value)
                }
            } catch {
                // /joint_states may not exist for all robots — fail silently
            }
        }
        subscriptionTasks.append(jointTask)

        // TF tracking — position the robot in the 3D scene
        let tfTask = Task { [weak self] in
            guard let self else { return }
            let rootLink = robotModel?.rootLink ?? "base_footprint"
            while !Task.isCancelled {
                if let tf = await tfTree.lookup(from: rootLink, to: fixedFrame, at: UInt64(Date().timeIntervalSince1970 * 1e9)) {
                    let q = simd_quatf(ix: Float(tf.rotation.imag.x), iy: Float(tf.rotation.imag.y), iz: Float(tf.rotation.imag.z), r: Float(tf.rotation.real))
                    let translation = SIMD3<Float>(tf.translation)
                    var base = simd_float4x4(q)
                    base.columns.3 = SIMD4<Float>(translation, 1)
                    await MainActor.run {
                        robotRenderer?.baseTransform = base
                    }
                }
                try? await Task.sleep(nanoseconds: 50_000_000) // 20 Hz
            }
        }
        subscriptionTasks.append(tfTask)
    }

    private func handleJointStates(_ data: Data) async {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let names    = obj["name"]     as? [String],
              let positions = obj["position"] as? [Double]
        else { return }

        var posMap: [String: Double] = [:]
        for (i, name) in names.enumerated() {
            guard i < positions.count else { break }
            posMap[name] = positions[i]
        }
        let state = JointState(positions: posMap)
        await MainActor.run {
            self.jointState = state
            self.messageCount += 1
        }
    }

    // MARK: - TF Frames

    private func subscribeTFFrames(_ layer: DisplayLayer) {
        // The TFTree actor is continuously populated by AppServices (which subscribes to /tf
        // and /tf_static). Here we poll at 10 Hz so axes move smoothly with the robot.
        let layerID = layer.id.uuidString
        let task = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.handleTFFrames(layerID: layerID)
                try? await Task.sleep(nanoseconds: 100_000_000) // 10 Hz
            }
        }
        subscriptionTasks.append(task)
    }

    private func handleTFFrames(layerID: String) async {
        guard let layer = activeLayers.first(where: { $0.id.uuidString == layerID }) else { return }
        let settings = layer.settings

        let frameNames = await tfTree.frames()
        guard !frameNames.isEmpty else { return }

        // Build edge metadata once per tick for static detection and parent lookup.
        let edgesMeta = await tfTree.edgesWithMetadata()
        // childrenSet: frames that have a parent (i.e. not the root)
        let childrenSet = Set(edgesMeta.map { $0.child })
        // isStaticMap: child frame → static flag
        var isStaticMap: [String: Bool] = [:]
        // parentMap: child frame → parent frame (for connection lines)
        var parentMap: [String: String] = [:]
        // stalenessMap: child frame → brightness multiplier (1.0=fresh, 0.6=aging, 0.3=stale)
        var stalenessMap: [String: Float] = [:]
        // Use per-layer settings (with sensible fallbacks if layer not found)
        let freshThresh = max(0.1, settings.tfFreshThresholdSec)
        let staleThresh = max(freshThresh + 0.1, settings.tfStaleThresholdSec)
        let nowNsForStaleness = UInt64(Date().timeIntervalSince1970 * 1_000_000_000)
        for edge in edgesMeta {
            isStaticMap[edge.child] = edge.isStatic
            parentMap[edge.child] = edge.parent
            if edge.isStatic {
                stalenessMap[edge.child] = 1.0
            } else if edge.receivedAtNs > 0, nowNsForStaleness > edge.receivedAtNs {
                let ageSec = Double(nowNsForStaleness - edge.receivedAtNs) / 1e9
                if ageSec < freshThresh {
                    stalenessMap[edge.child] = 1.0
                } else if ageSec < staleThresh {
                    stalenessMap[edge.child] = 0.6  // aging — dim
                } else {
                    stalenessMap[edge.child] = 0.3  // stale — very dim
                }
            } else {
                stalenessMap[edge.child] = 1.0
            }
        }

        let axisLength = Float(settings.axisLength)
        let opacity = Float(settings.opacity)
        let axisPoints = max(10, Int(40 * settings.axisLineWidth))  // width multiplier
        let hiddenFrames = settings.hiddenFrames
        let arrowTipKey = layerID + "__tips__"

        // Frame color mode: 0 = standard RGB, 1 = by depth, 2 = static/dynamic
        let colorMode = settings.frameColorMode

        // Compute depth from root for each frame (BFS from roots)
        var depthFromRoot: [String: Int] = [:]
        if colorMode == 1 {
            // BFS from roots (frames with no parent in parentMap)
            let roots = frameNames.filter { !($0).isEmpty && !(parentMap[$0] != nil) }
            var queue: [(String, Int)] = roots.map { ($0, 0) }
            var visited = Set<String>()
            while !queue.isEmpty {
                let (frame, depth) = queue.removeFirst()
                if visited.contains(frame) { continue }
                visited.insert(frame)
                depthFromRoot[frame] = depth
                // Find children of this frame
                for (child, parent) in parentMap {
                    if parent == frame && !visited.contains(child) {
                        queue.append((child, depth + 1))
                    }
                }
            }
        }

        var positionBytes = Data(capacity: frameNames.count * 3 * axisPoints * 12)
        var colorBytes    = Data(capacity: frameNames.count * 3 * axisPoints * 4)
        // Separate buffer for large arrowhead tip dots
        var tipPositionBytes = Data(capacity: frameNames.count * 3 * 12)
        var tipColorBytes    = Data(capacity: frameNames.count * 3 * 4)
        var count = 0
        var tipCount = 0
        let nowNs = UInt64(Date().timeIntervalSince1970 * 1e9)
        let refFrame = fixedFrame

        // Collect Metal-space origins for label overlay and connection lines
        var frameOrigins: [String: SIMD3<Float>] = [:]

        // Collect axis data per-frame for label overlay
        var frameAxisData: [String: (origin: SIMD3<Float>, xAxis: SIMD3<Float>, yAxis: SIMD3<Float>, zAxis: SIMD3<Float>, length: Float)] = [:]

        func clamp8(_ v: Float) -> UInt8 { UInt8(max(0, min(255, v))) }

        for frameName in frameNames {
            if hiddenFrames.contains(frameName) { continue }

            let t = await tfTree.lookup(from: frameName, to: refFrame, at: nowNs)

            var origin = SIMD3<Float>.zero
            var xAxis  = SIMD3<Float>(0, 0, 1)
            var yAxis  = SIMD3<Float>(-1, 0, 0)
            var zAxis  = SIMD3<Float>(0, 1, 0)

            if let tf = t {
                let (ox, oy, oz) = swizzle(Float(tf.translation.x), Float(tf.translation.y), Float(tf.translation.z))
                origin = SIMD3(ox, oy, oz)

                let rot = tf.rotation
                let rxRos = rot.act(SIMD3<Double>(1, 0, 0))
                let ryRos = rot.act(SIMD3<Double>(0, 1, 0))
                let rzRos = rot.act(SIMD3<Double>(0, 0, 1))

                let (xx, xy, xz) = swizzle(Float(rxRos.x), Float(rxRos.y), Float(rxRos.z))
                let (yx, yy, yz) = swizzle(Float(ryRos.x), Float(ryRos.y), Float(ryRos.z))
                let (zx, zy, zz) = swizzle(Float(rzRos.x), Float(rzRos.y), Float(rzRos.z))
                xAxis = SIMD3(xx, xy, xz)
                yAxis = SIMD3(yx, yy, yz)
                zAxis = SIMD3(zx, zy, zz)
            }

            frameOrigins[frameName] = origin

            // FIX-6: static frames at 45% brightness; dynamic at full
            let isStatic = isStaticMap[frameName] ?? false
            let staleMul = stalenessMap[frameName] ?? 1.0
            let chainMul: Float = {
                guard let chain = highlightedChain else { return 1.0 }
                return chain.contains(frameName) ? 1.0 : 0.15
            }()
            let brightMul: Float = (isStatic ? 0.45 : 1.0) * staleMul * chainMul

            // FIX-ROOT: root frame (no parent) rendered at 1.5× size + 20% brighter
            let isRoot = !childrenSet.contains(frameName)
            let scaleMul: Float = isRoot ? 1.5 : 1.0
            let rootBright: Float = isRoot ? 1.2 : 1.0

            let effectiveAxisLength = axisLength * scaleMul
            frameAxisData[frameName] = (origin, xAxis, yAxis, zAxis, effectiveAxisLength)

            // Compute axis colors based on frameColorMode
            let bm = brightMul * rootBright * opacity
            let dm = brightMul * opacity

            let axisColorTriples: [(SIMD3<Float>, (UInt8, UInt8, UInt8))] = {
                switch colorMode {
                case 1:
                    // By depth from root: cycle through hues
                    let depth = depthFromRoot[frameName] ?? 0
                    let hueShift = Float(depth) * 0.15
                    // Rotate RGB: depth 0=normal, 1=shifted, etc.
                    let r = clamp8((230 + hueShift * 50) * bm)
                    let g = clamp8((50 + hueShift * 80) * dm)
                    let b = clamp8((50 + hueShift * 100) * dm)
                    return [
                        (xAxis, (r, clamp8(50 * dm), clamp8(50 * dm))),
                        (yAxis, (clamp8(50 * dm), g, clamp8(50 * dm))),
                        (zAxis, (clamp8(50 * dm), clamp8(80 * dm), b))
                    ]
                case 2:
                    // Static=teal, dynamic=orange
                    if isStatic {
                        return [
                            (xAxis, (clamp8(30 * bm), clamp8(180 * bm), clamp8(170 * bm))),
                            (yAxis, (clamp8(30 * dm), clamp8(200 * bm), clamp8(190 * bm))),
                            (zAxis, (clamp8(20 * dm), clamp8(160 * bm), clamp8(150 * bm)))
                        ]
                    } else {
                        return [
                            (xAxis, (clamp8(240 * bm), clamp8(120 * dm), clamp8(30 * dm))),
                            (yAxis, (clamp8(220 * dm), clamp8(140 * bm), clamp8(30 * dm))),
                            (zAxis, (clamp8(200 * dm), clamp8(100 * dm), clamp8(20 * bm)))
                        ]
                    }
                default:
                    // Standard RGB axes: X=red, Y=green, Z=blue
                    return [
                        (xAxis, (clamp8(230 * bm), clamp8(50 * dm), clamp8(50 * dm))),
                        (yAxis, (clamp8(50 * dm), clamp8(200 * bm), clamp8(50 * dm))),
                        (zAxis, (clamp8(50 * dm), clamp8(80 * dm), clamp8(230 * bm)))
                    ]
                }
            }()

            // Per-axis visibility
            let visibleAxes: [(SIMD3<Float>, (UInt8, UInt8, UInt8))] = [
                (settings.axisShowX ? axisColorTriples[0].0 : SIMD3<Float>.zero, axisColorTriples[0].1),
                (settings.axisShowY ? axisColorTriples[1].0 : SIMD3<Float>.zero, axisColorTriples[1].1),
                (settings.axisShowZ ? axisColorTriples[2].0 : SIMD3<Float>.zero, axisColorTriples[2].1)
            ]

            for (dir, rgb) in visibleAxes {
                guard dir != SIMD3<Float>.zero else { continue }  // skip hidden axes
                for step in 0..<axisPoints {
                    let frac = Float(step) / Float(axisPoints - 1)
                    let p = origin + dir * (frac * effectiveAxisLength)
                    var px = p.x, py = p.y, pz = p.z
                    withUnsafeBytes(of: &px) { positionBytes.append(contentsOf: $0) }
                    withUnsafeBytes(of: &py) { positionBytes.append(contentsOf: $0) }
                    withUnsafeBytes(of: &pz) { positionBytes.append(contentsOf: $0) }
                    colorBytes.append(rgb.0)
                    colorBytes.append(rgb.1)
                    colorBytes.append(rgb.2)
                    colorBytes.append(255)  // opaque — brightness is in RGB
                    count += 1
                }
                // Arrowhead tip at the axis end
                let tip = origin + dir * effectiveAxisLength
                let nodeSize = Float(settings.frameNodeSize)
                switch settings.frameNodeShape {
                case 1:
                    // Diamond: 4 points offset in a diamond pattern
                    let offsets: [(Float, Float)] = [(0, nodeSize * 0.02), (nodeSize * 0.015, 0), (0, -nodeSize * 0.02), (-nodeSize * 0.015, 0)]
                    for (ox, oy) in offsets {
                        let tp = tip + SIMD3<Float>(ox, oy, 0)
                        var tx = tp.x, ty = tp.y, tz = tp.z
                        withUnsafeBytes(of: &tx) { tipPositionBytes.append(contentsOf: $0) }
                        withUnsafeBytes(of: &ty) { tipPositionBytes.append(contentsOf: $0) }
                        withUnsafeBytes(of: &tz) { tipPositionBytes.append(contentsOf: $0) }
                        tipColorBytes.append(rgb.0)
                        tipColorBytes.append(rgb.1)
                        tipColorBytes.append(rgb.2)
                        tipColorBytes.append(255)
                        tipCount += 1
                    }
                case 2:
                    // Cross: 5 points in a cross pattern
                    let offsets: [(Float, Float)] = [(0, 0), (nodeSize * 0.02, 0), (-nodeSize * 0.02, 0), (0, nodeSize * 0.02), (0, -nodeSize * 0.02)]
                    for (ox, oy) in offsets {
                        let tp = tip + SIMD3<Float>(ox, oy, 0)
                        var tx = tp.x, ty = tp.y, tz = tp.z
                        withUnsafeBytes(of: &tx) { tipPositionBytes.append(contentsOf: $0) }
                        withUnsafeBytes(of: &ty) { tipPositionBytes.append(contentsOf: $0) }
                        withUnsafeBytes(of: &tz) { tipPositionBytes.append(contentsOf: $0) }
                        tipColorBytes.append(rgb.0)
                        tipColorBytes.append(rgb.1)
                        tipColorBytes.append(rgb.2)
                        tipColorBytes.append(255)
                        tipCount += 1
                    }
                default:
                    // Dot: single point
                    var tx = tip.x, ty = tip.y, tz = tip.z
                    withUnsafeBytes(of: &tx) { tipPositionBytes.append(contentsOf: $0) }
                    withUnsafeBytes(of: &ty) { tipPositionBytes.append(contentsOf: $0) }
                    withUnsafeBytes(of: &tz) { tipPositionBytes.append(contentsOf: $0) }
                    tipColorBytes.append(rgb.0)
                    tipColorBytes.append(rgb.1)
                    tipColorBytes.append(rgb.2)
                    tipColorBytes.append(255)
                    tipCount += 1
                }
            }
        }

        // FIX-4: parent→child connection lines (with width, style, color)
        if settings.showFrameLinks {
            let linePoints = max(4, Int(10 * settings.linkLineWidth))
            let lineR = Float(settings.linkLineR)
            let lineG = Float(settings.linkLineG)
            let lineB = Float(settings.linkLineB)
            let isDashed = settings.linkLineStyle == 1
            for (child, parent) in parentMap {
                if hiddenFrames.contains(child) || hiddenFrames.contains(parent) { continue }
                guard let childOrigin = frameOrigins[child],
                      let parentOrigin = frameOrigins[parent] else { continue }
                // Dim non-chain connection lines when a chain is highlighted
                var chainDim: Float = 1.0
                if let chain = highlightedChain {
                    let inChain = chain.contains(child) && chain.contains(parent)
                    if !inChain { chainDim = 0.15 }
                }
                for step in 0..<linePoints {
                    // Dashed: skip every 3rd point to create gaps
                    if isDashed && step % 3 == 1 { continue }
                    let frac = Float(step) / Float(linePoints - 1)
                    let p = parentOrigin + (childOrigin - parentOrigin) * frac
                    var px = p.x, py = p.y, pz = p.z
                    withUnsafeBytes(of: &px) { positionBytes.append(contentsOf: $0) }
                    withUnsafeBytes(of: &py) { positionBytes.append(contentsOf: $0) }
                    withUnsafeBytes(of: &pz) { positionBytes.append(contentsOf: $0) }
                    colorBytes.append(clamp8(lineR * 255 * chainDim))
                    colorBytes.append(clamp8(lineG * 255 * chainDim))
                    colorBytes.append(clamp8(lineB * 255 * chainDim))
                    colorBytes.append(clamp8(180 * opacity))
                    count += 1
                }
            }
        }

        let layerUUID = UUID(uuidString: layerID)
        let sortedOrigins = frameOrigins.map { (id: $0.key, metal: $0.value) }
        let allFramesSorted = frameNames.sorted()

        guard count > 0 else {
            let emptyFrame = PointCloudFrame(pointCount: 0, positions: Data(),
                                             intensities: nil, colors: Data(),
                                             pointSize: 2.0, colorMode: .rgb)
            await MainActor.run {
                self.pointCloudRenderer?.update(topic: layerID, frame: emptyFrame)
                self.pointCloudRenderer?.clearTopic(arrowTipKey)
                self.tfFrameWorldPositions = []
                self.tfFrameAxisData = [:]
                self.knownTFFrames = allFramesSorted
            }
            return
        }

        let axisPointSize: Float = max(1.0, Float(2.0 * settings.axisLineWidth))
        let cloudFrame = PointCloudFrame(pointCount: count, positions: positionBytes,
                                          intensities: nil, colors: colorBytes,
                                          pointSize: axisPointSize, colorMode: .rgb)
        let tipFrame = PointCloudFrame(pointCount: tipCount, positions: tipPositionBytes,
                                       intensities: nil, colors: tipColorBytes,
                                       pointSize: Float(settings.frameNodeSize), colorMode: .rgb)

        await MainActor.run {
            self.pointCloudRenderer?.update(topic: layerID, frame: cloudFrame)
            self.pointCloudRenderer?.update(topic: arrowTipKey, frame: tipFrame)
            self.tfFrameWorldPositions = sortedOrigins
            self.tfFrameAxisData = frameAxisData
            self.knownTFFrames = allFramesSorted
            if let id = layerUUID { self.recordMessageReceived(layerID: id) }
        }
    }

    // MARK: - Trail helper (Odometry / PoseStamped)

    /// Push a single 3-float point onto the trail for `layerID`.
    /// - Parameter trailLength: Maximum number of poses (0 = unlimited / use decaySeconds only).
    private func pushTrailPoint(_ pointData: Data, layerID: UUID, trailLength: Int = 0) async {
        guard let layer = activeLayers.first(where: { $0.id == layerID }) else { return }
        let now = Date()
        let key = layerID.uuidString
        var trail = layerTrails[key] ?? []
        trail.append((timestamp: now, data: pointData))

        // Prune by decay using current settings (live from activeLayers)
        if layer.settings.decaySeconds > 0 {
            let cutoff = now.addingTimeInterval(-layer.settings.decaySeconds)
            trail.removeAll { $0.timestamp < cutoff }
        } else if trailLength > 0 {
            // Cap by count when no time-based decay
            while trail.count > trailLength {
                trail.removeFirst()
            }
        } else {
            // Latest-frame-only: keep just the most recent point
            trail = [trail.last!]
        }
        layerTrails[key] = trail

        var positionBytes = Data(capacity: trail.count * 12)
        for entry in trail {
            positionBytes.append(entry.data)
        }

        let frameData = positionBytes
        let count = trail.count
        let cloudFrame = PointCloudFrame(pointCount: count, positions: frameData,
                                         intensities: nil, colors: nil,
                                         pointSize: layer.settings.pointSize,
                                         colorMode: colorMode(for: layer.settings))
        await MainActor.run {
            self.pointCloudRenderer?.update(topic: key, frame: cloudFrame)
            self.messageCount += 1
            self.recordMessageReceived(layerID: layerID)
        }
    }
}

// MARK: - Private helpers

/// Derives the `PointColorMode` to use for a layer from its `LayerSettings`.
/// Always uses `.constant` so the color picker in the Layers panel is reflected
/// immediately in the Metal canvas (previously the renderer ignored these values).
private func colorMode(for settings: LayerSettings) -> PointColorMode {
    .constant(.init(Float(settings.r), Float(settings.g), Float(settings.b),
                    Float(settings.opacity)))
}

// MARK: - Data helpers

private extension Data {
    /// Build a Data block from an array of Floats (3 floats = one XYZ point).
    init(floats: [Float]) {
        self.init(capacity: floats.count * 4)
        for f in floats {
            var v = f
            Swift.withUnsafeBytes(of: &v) { self.append(contentsOf: $0) }
        }
    }
}
