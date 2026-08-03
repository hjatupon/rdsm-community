import Foundation
import simd
import Observation
import Transport
import TopicStore
import MessageRegistry
import ChartingCore
import LogStore

/// View-model for ``InspectorView``.
///
/// - Resolves the render kind once from the schema name.
/// - Subscribes to the topic on appear; unsubscribes on disappear.
/// - Decodes each incoming ``TopicMessage`` payload and routes to typed state.
@Observable
@MainActor
public final class InspectorViewModel {

    // MARK: - Public state

    public private(set) var renderKind: RenderKind = .jsonTree
    public private(set) var latestPayload: Data? = nil
    public private(set) var jsonRoots: [FieldNode] = []
    public private(set) var messageCount: UInt64 = 0
    public private(set) var hz: Double = 0
    public private(set) var isSubscribed: Bool = false
    public private(set) var subscriptionError: String? = nil
    /// Wall-clock time of the most recent display update (nil until first message).
    public private(set) var latestTimestamp: Date? = nil

    // MARK: - Pause / throttle controls

    /// When true the display is frozen; the subscription continues draining.
    public private(set) var isPaused: Bool = false
    /// Display update interval in seconds.  0 = live (every message).
    public private(set) var throttleSeconds: Double = 0

    // Numeric chart (shared buffer — view reads, ViewModel writes)
    public private(set) var chartSeries: ChartSeries
    public private(set) var latestScalar: Double? = nil

    // Bool
    public private(set) var latestBool: Bool? = nil

    // String
    public private(set) var latestString: String? = nil

    // Log
    public private(set) var logEntries: [LogEntry] = []

    // Range sensor
    public private(set) var rangeValue: Double? = nil
    public private(set) var rangeMin: Double? = nil
    public private(set) var rangeMax: Double? = nil

    // Battery
    public private(set) var batteryPercentage: Double? = nil
    public private(set) var batteryVoltage: Double? = nil
    public private(set) var batteryCurrent: Double? = nil

    // LaserScan
    public private(set) var scanRanges: [Float] = []
    public private(set) var scanAngleMin: Double = 0
    public private(set) var scanAngleMax: Double = 0
    public private(set) var scanRangeMin: Double = 0
    public private(set) var scanRangeMax: Double = 0

    // Odometry
    public private(set) var odomPosition: SIMD3<Double> = .zero
    public private(set) var odomRPY: SIMD3<Double> = .zero         // radians
    public private(set) var odomLinearVel: SIMD3<Double> = .zero
    public private(set) var odomAngularVel: SIMD3<Double> = .zero
    public private(set) var odomPositionTrail: [SIMD2<Double>] = []

    // IMU
    public private(set) var imuRPY: SIMD3<Double> = .zero          // radians
    public private(set) var imuAngularVel: SIMD3<Double> = .zero
    public private(set) var imuLinearAccel: SIMD3<Double> = .zero

    // Twist / TwistStamped
    public private(set) var twistLinear: SIMD3<Double> = .zero
    public private(set) var twistAngular: SIMD3<Double> = .zero

    // OccupancyGrid
    public private(set) var gridWidth: Int = 0
    public private(set) var gridHeight: Int = 0
    public private(set) var gridResolution: Double = 0.05
    public private(set) var gridData: [Int8] = []

    // JointState
    public private(set) var jointNames: [String] = []
    public private(set) var jointPositions: [Double] = []
    public private(set) var jointVelocities: [Double] = []
    public private(set) var jointEfforts: [Double] = []

    // DiagnosticArray
    public private(set) var diagnosticItems: [DiagnosticItem] = []

    // Odometry velocity series (for OdometryView chart)
    public private(set) var odomVelSeries: ChartSeries

    // MARK: - TF Tree summary

    /// Summary data for /tf topics, computed from the raw TF message payload.
    public struct TFSummary: Sendable, Equatable {
        public let frameCount: Int
        public let rootCount: Int
        public let edgeCount: Int
        public let avgHz: Double
        public let staleCount: Int
        public let roots: [String]
        public let hasData: Bool

        public static let empty = TFSummary(frameCount: 0, rootCount: 0, edgeCount: 0, avgHz: 0,
                                             staleCount: 0, roots: [], hasData: false)
    }

    public private(set) var tfSummary: TFSummary = .empty

    // MARK: - Private

    private let store: TopicStore
    private let registry: any MessageRegistry
    private let topic: TopicDescriptor
    private let resolver: RenderKindResolver
    private var subscriptionTask: Task<Void, Never>?
    private var hzTimer: Task<Void, Never>?
    private var recentTimestamps: [UInt64] = []

    /// Timestamp of the most recent display update (used for throttling).
    private var lastDisplayUpdateNs: UInt64 = 0

    /// Mutable cap set by the user via the UI cap picker (default 1000).
    var maxLogEntries: Int = 1000

    public init(store: TopicStore,
                registry: any MessageRegistry,
                topic: TopicDescriptor) {
        self.store = store
        self.registry = registry
        self.topic = topic
        self.resolver = RenderKindResolver()
        self.renderKind = resolver.resolve(schemaName: topic.schemaName)
        let chartCap = { let v = UserDefaults.standard.integer(forKey: "perf.chartHistoryPoints"); return v > 0 ? v : 2000 }()
        self.chartSeries = ChartSeries(
            id: topic.schemaName,
            color: SIMD4<Float>(0.18, 0.73, 0.69, 1.0),
            capacity: chartCap)
        self.odomVelSeries = ChartSeries(
            id: topic.schemaName + ".vel",
            color: SIMD4<Float>(0.18, 0.73, 0.69, 1.0),
            capacity: chartCap)
        self.vizOverrideID = VizOverrideStore.shared.override(for: topic.name)
    }

    // MARK: - Lifecycle

    public func startSubscription() async {
        guard subscriptionTask == nil else { return }
        isSubscribed = false
        subscriptionError = nil

        subscriptionTask = Task { [weak self] in
            guard let self else { return }
            do {
                let stream = try await store.rawMessageStream(for: topic.name)
                await MainActor.run { self.isSubscribed = true }
                for await msg in stream {
                    await self.handle(msg)
                }
            } catch {
                await MainActor.run {
                    self.subscriptionError = error.localizedDescription
                    self.isSubscribed = false
                }
            }
        }

        startHzTimer()
    }

    public func stopSubscription() {
        subscriptionTask?.cancel()
        subscriptionTask = nil
        hzTimer?.cancel()
        hzTimer = nil
        isSubscribed = false
    }

    // MARK: - Pause / throttle API

    /// Freeze the display at the current message.  Subscription stays active.
    public func setPaused(_ paused: Bool) {
        isPaused = paused
    }

    /// Set the minimum interval between display updates.  0 = live.
    public func setThrottle(_ seconds: Double) {
        throttleSeconds = max(0, seconds)
    }

    /// Clear both pause and throttle — return to live full-speed display.
    public func resetThrottling() {
        isPaused = false
        throttleSeconds = 0
        lastDisplayUpdateNs = 0
    }

    /// Clear all accumulated log entries (triggered by the Log filter bar's Clear button).
    public func clearLogEntries() {
        logEntries.removeAll()
    }

    // MARK: - Visualization override API

    /// The currently active override descriptor ID, or nil if using auto-detection.
    /// Stored as @Observable so InspectorView re-renders automatically on change.
    public private(set) var vizOverrideID: String?

    /// Persists a visualization override for this topic and triggers a live view update.
    public func setVizOverride(_ id: String) {
        VizOverrideStore.shared.set(vizID: id, for: topic.name)
        vizOverrideID = id
    }

    /// Removes the override — reverts to the auto-detected visualization.
    public func resetVizOverride() {
        VizOverrideStore.shared.reset(for: topic.name)
        vizOverrideID = nil
    }

    /// Snapshot of all typed state — used by the viz picker modal for static previews
    /// and by the live inspector content when a custom visualization is active.
    public func snapshotState() -> VisualizationSnapshot {
        VisualizationSnapshot(
            schemaName: topic.schemaName,
            autoRenderKind: renderKind,
            latestPayload: latestPayload,
            jsonRoots: jsonRoots,
            messageCount: messageCount,
            hz: hz,
            latestScalar: latestScalar,
            chartSeries: chartSeries,
            latestBool: latestBool,
            latestString: latestString,
            logEntries: logEntries,
            rangeValue: rangeValue, rangeMin: rangeMin, rangeMax: rangeMax,
            batteryPercentage: batteryPercentage, batteryVoltage: batteryVoltage,
            batteryCurrent: batteryCurrent,
            scanRanges: scanRanges, scanAngleMin: scanAngleMin, scanAngleMax: scanAngleMax,
            scanRangeMin: scanRangeMin, scanRangeMax: scanRangeMax,
            odomPosition: odomPosition, odomRPY: odomRPY,
            odomLinearVel: odomLinearVel, odomAngularVel: odomAngularVel,
            odomPositionTrail: odomPositionTrail,
            odomVelSeries: odomVelSeries,
            imuRPY: imuRPY, imuAngularVel: imuAngularVel, imuLinearAccel: imuLinearAccel,
            twistLinear: twistLinear, twistAngular: twistAngular,
            gridWidth: gridWidth, gridHeight: gridHeight, gridResolution: gridResolution,
            gridData: gridData,
            jointNames: jointNames, jointPositions: jointPositions,
            jointVelocities: jointVelocities, jointEfforts: jointEfforts,
            diagnosticItems: diagnosticItems)
    }

    // MARK: - Private

    private func handle(_ msg: Timestamped<TopicMessage>) async {
        let payload = msg.value.payload
        let ts = msg.timestamp

        await MainActor.run {
            // Always update meta-stats so Hz and count remain live.
            self.messageCount += 1
            self.recentTimestamps.append(ts)
            let cutoff = ts > 2_000_000_000 ? ts - 2_000_000_000 : 0
            self.recentTimestamps.removeAll { $0 < cutoff }

            // Gate the display update on pause and throttle.
            if self.isPaused { return }
            if self.throttleSeconds > 0 {
                let intervalNs = UInt64(self.throttleSeconds * 1_000_000_000)
                guard ts >= self.lastDisplayUpdateNs + intervalNs else { return }
            }
            self.lastDisplayUpdateNs = ts

            self.latestPayload = payload
            self.latestTimestamp = Date()

            // Always keep raw JSON tree available for the Raw toggle.
            self.jsonRoots = FieldNode.fromJSON(payload)

            let dict = (try? JSONSerialization.jsonObject(with: payload) as? [String: Any]) ?? [:]
            let t = Double(ts) / 1_000_000_000.0

            switch self.renderKind {
            case .image:
                break

            case .numericScalar:
                let v = Self.extractScalar(from: dict)
                self.latestScalar = v
                self.chartSeries.buffer.push(ChartPoint(t: t, value: v ?? 0))

            case .boolean:
                self.latestBool = Self.extractBool(from: dict)

            case .stringValue:
                self.latestString = dict["data"] as? String

            case .logMessage:
                if let entry = Self.parseLogEntry(from: dict, fallbackTimestampNs: ts) {
                    self.logEntries.append(entry)
                    if self.logEntries.count > self.maxLogEntries {
                        self.logEntries.removeFirst(self.logEntries.count - self.maxLogEntries)
                    }
                }

            case .rangeGauge:
                self.rangeValue = Self.extractField("range", from: dict)
                self.rangeMin   = Self.extractField("min_range", from: dict)
                self.rangeMax   = Self.extractField("max_range", from: dict)

            case .batteryState:
                self.batteryPercentage = Self.extractField("percentage", from: dict)
                self.batteryVoltage    = Self.extractField("voltage", from: dict)
                self.batteryCurrent    = Self.extractField("current", from: dict)

            case .laserScan:
                if let arr = dict["ranges"] as? [Any] {
                    self.scanRanges = arr.compactMap { v -> Float? in
                        if let n = v as? NSNumber { return n.floatValue }
                        return nil
                    }
                }
                self.scanAngleMin  = Self.extractField("angle_min",  from: dict) ?? 0
                self.scanAngleMax  = Self.extractField("angle_max",  from: dict) ?? 0
                self.scanRangeMin  = Self.extractField("range_min",  from: dict) ?? 0
                self.scanRangeMax  = Self.extractField("range_max",  from: dict) ?? 0

            case .odometry:
                if let pose = dict["pose"] as? [String: Any],
                   let poseInner = pose["pose"] as? [String: Any] {
                    if let pos = poseInner["position"] as? [String: Any] {
                        self.odomPosition = SIMD3(
                            Self.extractField("x", from: pos) ?? 0,
                            Self.extractField("y", from: pos) ?? 0,
                            Self.extractField("z", from: pos) ?? 0)
                    }
                    if let ori = poseInner["orientation"] as? [String: Any] {
                        let qx = Self.extractField("x", from: ori) ?? 0
                        let qy = Self.extractField("y", from: ori) ?? 0
                        let qz = Self.extractField("z", from: ori) ?? 0
                        let qw = Self.extractField("w", from: ori) ?? 1
                        self.odomRPY = Self.quaternionToRPY(qx: qx, qy: qy, qz: qz, qw: qw)
                    }
                }
                if let twist = dict["twist"] as? [String: Any],
                   let twistInner = twist["twist"] as? [String: Any] {
                    if let lin = twistInner["linear"] as? [String: Any] {
                        self.odomLinearVel = SIMD3(
                            Self.extractField("x", from: lin) ?? 0,
                            Self.extractField("y", from: lin) ?? 0,
                            Self.extractField("z", from: lin) ?? 0)
                    }
                    if let ang = twistInner["angular"] as? [String: Any] {
                        self.odomAngularVel = SIMD3(
                            Self.extractField("x", from: ang) ?? 0,
                            Self.extractField("y", from: ang) ?? 0,
                            Self.extractField("z", from: ang) ?? 0)
                    }
                }
                // Accumulate 2D trail (last 100 points)
                let pt = SIMD2(self.odomPosition.x, self.odomPosition.y)
                if self.odomPositionTrail.last != pt {
                    self.odomPositionTrail.append(pt)
                    if self.odomPositionTrail.count > 100 {
                        self.odomPositionTrail.removeFirst(self.odomPositionTrail.count - 100)
                    }
                }
                // Push linear.x velocity to chart series
                self.odomVelSeries.buffer.push(ChartPoint(t: t, value: self.odomLinearVel.x))

            case .imu:
                if let ori = dict["orientation"] as? [String: Any] {
                    let qx = Self.extractField("x", from: ori) ?? 0
                    let qy = Self.extractField("y", from: ori) ?? 0
                    let qz = Self.extractField("z", from: ori) ?? 0
                    let qw = Self.extractField("w", from: ori) ?? 1
                    self.imuRPY = Self.quaternionToRPY(qx: qx, qy: qy, qz: qz, qw: qw)
                }
                if let gyro = dict["angular_velocity"] as? [String: Any] {
                    self.imuAngularVel = SIMD3(
                        Self.extractField("x", from: gyro) ?? 0,
                        Self.extractField("y", from: gyro) ?? 0,
                        Self.extractField("z", from: gyro) ?? 0)
                }
                if let accel = dict["linear_acceleration"] as? [String: Any] {
                    self.imuLinearAccel = SIMD3(
                        Self.extractField("x", from: accel) ?? 0,
                        Self.extractField("y", from: accel) ?? 0,
                        Self.extractField("z", from: accel) ?? 0)
                }

            case .twist:
                // Handle both Twist (direct) and TwistStamped (nested under "twist")
                let twistDict: [String: Any]
                if let nested = dict["twist"] as? [String: Any] {
                    twistDict = nested
                } else {
                    twistDict = dict
                }
                if let lin = twistDict["linear"] as? [String: Any] {
                    self.twistLinear = SIMD3(
                        Self.extractField("x", from: lin) ?? 0,
                        Self.extractField("y", from: lin) ?? 0,
                        Self.extractField("z", from: lin) ?? 0)
                }
                if let ang = twistDict["angular"] as? [String: Any] {
                    self.twistAngular = SIMD3(
                        Self.extractField("x", from: ang) ?? 0,
                        Self.extractField("y", from: ang) ?? 0,
                        Self.extractField("z", from: ang) ?? 0)
                }

            case .occupancyGrid:
                if let info = dict["info"] as? [String: Any] {
                    self.gridWidth      = (info["width"]  as? Int) ?? 0
                    self.gridHeight     = (info["height"] as? Int) ?? 0
                    self.gridResolution = Self.extractField("resolution", from: info) ?? 0.05
                }
                if let dataArr = dict["data"] as? [Any] {
                    self.gridData = dataArr.map { v -> Int8 in
                        if let n = v as? NSNumber { return Int8(clamping: n.int32Value) }
                        return -1
                    }
                }

            case .jointState:
                if let names = dict["name"] as? [String] {
                    self.jointNames = names
                }
                if let positions = dict["position"] as? [Any] {
                    self.jointPositions = positions.compactMap { v -> Double? in
                        if let n = v as? NSNumber { return n.doubleValue }
                        return nil
                    }
                }
                if let velocities = dict["velocity"] as? [Any] {
                    self.jointVelocities = velocities.compactMap { v -> Double? in
                        if let n = v as? NSNumber { return n.doubleValue }
                        return nil
                    }
                }
                if let efforts = dict["effort"] as? [Any] {
                    self.jointEfforts = efforts.compactMap { v -> Double? in
                        if let n = v as? NSNumber { return n.doubleValue }
                        return nil
                    }
                }

            case .diagnosticArray:
                if let statusArr = dict["status"] as? [[String: Any]] {
                    self.diagnosticItems = statusArr.map { s -> DiagnosticItem in
                        let level = (s["level"] as? NSNumber)?.intValue ?? 0
                        let name = s["name"] as? String ?? ""
                        let hwid = s["hardware_id"] as? String ?? ""
                        let message = s["message"] as? String ?? ""
                        var kvPairs: [(String, String)] = []
                        if let vals = s["values"] as? [[String: Any]] {
                            kvPairs = vals.compactMap { v -> (String, String)? in
                                guard let k = v["key"] as? String,
                                      let val = v["value"] as? String else { return nil }
                                return (k, val)
                            }
                        }
                        return DiagnosticItem(level: level, name: name,
                                              hardwareId: hwid, message: message, values: kvPairs)
                    }
                }

            case .tfTree:
                // Parse TF summary from the raw message for the inspector summary card
                if let transforms = dict["transforms"] as? [[String: Any]] {
                    var childFrames = Set<String>()
                    var parentFrames = Set<String>()
                    for tf in transforms {
                        if let child = tf["child_frame_id"] as? String {
                            childFrames.insert(child)
                        }
                        if let header = tf["header"] as? [String: Any],
                           let frame = header["frame_id"] as? String {
                            parentFrames.insert(frame)
                        }
                    }
                    let allChildren = Set(childFrames)
                    let allParents = Set(parentFrames)
                    let roots = allParents.subtracting(allChildren).sorted()
                    let totalEdgeCount = transforms.count
                    // Compute Hz from the most recent 2-second window
                    let hz: Double = {
                        guard recentTimestamps.count >= 2 else { return 0 }
                        let elapsed = Double(recentTimestamps.last! - recentTimestamps.first!) / 1e9
                        guard elapsed > 0 else { return 0 }
                        return Double(recentTimestamps.count - 1) / elapsed
                    }()
                    self.tfSummary = TFSummary(
                        frameCount: allChildren.union(allParents).count,
                        rootCount: roots.count,
                        edgeCount: totalEdgeCount,
                        avgHz: hz,
                        staleCount: 0,
                        roots: roots,
                        hasData: true)
                }

            case .jsonTree:
                if let schema = self.topic.schema,
                   let decoded = ROS2CDRDecoder.decode(data: payload, schema: schema),
                   let jsonData = try? JSONSerialization.data(withJSONObject: decoded) {
                    self.jsonRoots = FieldNode.fromJSON(jsonData)
                } else {
                    self.jsonRoots = FieldNode.fromJSON(payload)
                }
            }
        }
    }

    // MARK: - Parsing helpers

    private static func extractScalar(from dict: [String: Any]) -> Double? {
        if let v = dict["data"] as? Double { return v }
        if let v = dict["data"] as? Int    { return Double(v) }
        if let v = dict["data"] as? Bool   { return v ? 1.0 : 0.0 }
        return nil
    }

    private static func extractBool(from dict: [String: Any]) -> Bool? {
        if let v = dict["data"] as? Bool { return v }
        if let v = dict["data"] as? Int  { return v != 0 }
        return nil
    }

    /// ZYX intrinsic Euler angles from unit quaternion (ROS convention).
    /// Returns (roll, pitch, yaw) in radians.
    static func quaternionToRPY(qx: Double, qy: Double, qz: Double, qw: Double) -> SIMD3<Double> {
        let roll  = atan2(2 * (qw * qx + qy * qz), 1 - 2 * (qx * qx + qy * qy))
        let sinP  = Swift.max(-1, Swift.min(1, 2 * (qw * qy - qz * qx)))
        let pitch = asin(sinP)
        let yaw   = atan2(2 * (qw * qz + qx * qy), 1 - 2 * (qy * qy + qz * qz))
        return SIMD3(roll, pitch, yaw)
    }

    private static func extractField(_ key: String, from dict: [String: Any]) -> Double? {
        if let v = dict[key] as? Double { return v }
        if let v = dict[key] as? Int    { return Double(v) }
        if let v = dict[key] as? Float  { return Double(v) }
        return nil
    }

    private static func parseLogEntry(from dict: [String: Any],
                                      fallbackTimestampNs: UInt64) -> LogEntry? {
        guard let msgText = dict["msg"] as? String else { return nil }
        // rosbridge sends level as NSNumber — use NSNumber cast to avoid Int/Double mismatch
        let levelVal = (dict["level"] as? NSNumber)?.uint8Value ?? 20
        let severity = LogSeverity(raw: levelVal) ?? .info
        let node     = dict["name"]     as? String ?? ""
        let file     = dict["file"]     as? String ?? ""
        let function = dict["function"] as? String ?? ""
        let lineInt  = (dict["line"] as? NSNumber)?.uint32Value ?? 0

        var stampNs = fallbackTimestampNs
        if let stamp   = dict["stamp"]   as? [String: Any] {
            let sec     = (stamp["sec"]    as? NSNumber)?.uint64Value ?? 0
            let nanosec = (stamp["nanosec"] as? NSNumber)?.uint64Value ?? 0
            if sec > 0 {
                stampNs = sec * 1_000_000_000 + nanosec
            }
        }

        return LogEntry(
            timestampNs: stampNs,
            severity: severity,
            node: node,
            message: msgText,
            file: file,
            function: function,
            line: lineInt)
    }

    private func startHzTimer() {
        hzTimer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                await MainActor.run {
                    guard let self else { return }
                    guard self.recentTimestamps.count >= 2 else {
                        self.hz = 0
                        return
                    }
                    let elapsed = Double(self.recentTimestamps.last! - self.recentTimestamps.first!) / 1e9
                    guard elapsed > 0 else { self.hz = 0; return }
                    self.hz = Double(self.recentTimestamps.count - 1) / elapsed
                }
            }
        }
    }
}

// MARK: - DiagnosticItem

public struct DiagnosticItem: Sendable, Identifiable {
    public let id: UUID = UUID()
    public let level: Int       // 0=OK,1=WARN,2=ERROR,3=STALE
    public let name: String
    public let hardwareId: String
    public let message: String
    public let values: [(String, String)]
}

// MARK: - TopicStore raw stream bridge

private extension TopicStore {
    func rawMessageStream(for topic: String) async throws -> AsyncStream<Timestamped<TopicMessage>> {
        let raw = try await self.subscribePayload(topic)
        let (stream, cont) = AsyncStream<Timestamped<TopicMessage>>.makeStream()
        Task {
            for await stamped in raw {
                let msg = TopicMessage(
                    topic: topic,
                    timestamp: stamped.timestamp,
                    schemaName: "",
                    payload: stamped.value)
                cont.yield(Timestamped(timestamp: stamped.timestamp, value: msg))
            }
            cont.finish()
        }
        return stream
    }
}
