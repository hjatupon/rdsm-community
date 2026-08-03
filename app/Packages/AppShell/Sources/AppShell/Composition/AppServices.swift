import Combine
import Foundation
import simd
import Logging
import Transport
import MessageRegistry
import TopicStore
import TFTree
import ConnectionManager
import LayoutEngine
import ProfileStore
import LogStore
import MetalCore
import MeshLoader
import RobotModelCore
import RobotModelLoader
import URDFParser
import PublishService
import Viewer3DUI
import ServiceCallService
import ServiceCallUI

/// Single composition root — all Layer 3 actors live here and are injected
/// downward via protocol-typed arguments.
@MainActor
public final class AppServices: ObservableObject {
    public let logger: Logger
    let registry: DefaultMessageRegistry

    // Persists UI-level connection profiles (name, URL, Keychain secret reference).
    // Passed directly to ConnectionView — not bridged to ConnectionManager.
    let profileStore: ProfileStore

    // Manages live transport connections. Uses InMemoryProfileStore internally.
    let connectionManager: ConnectionManager

    let layoutEngine: LayoutEngine

    public let toasts = ToastCenter.shared
    let selection = SelectionStore()
    let recentConnectionsStore = RecentConnectionsStore()

    /// Last 3 distinct connections the user successfully connected to (MRU order).
    @Published var recentConnections: [RecentConnection] = []

    /// Current session mode — live robot connection or rosbag replay.
    /// Restored from UserDefaults on launch; persists across app restarts.
    @Published var sessionMode: SessionMode = {
        if let raw = UserDefaults.standard.string(forKey: "lastSessionMode"),
           let mode = SessionMode(rawValue: raw) {
            return mode
        }
        return .live
    }()

    /// Active TopicStore for the current session.
    @Published public var activeTopicStore: TopicStore?
    @Published var activeTFTree: TFTree?
    @Published var activePointCloudTopics: [String] = []
    @Published var activeLaserScanTopics: [String] = []
    /// All topics available in the current session.
    @Published public var availableTopics: [TopicDescriptor] = []
    /// Whether a rosbag replay session is currently active (drives replay UI).
    /// The concrete replay adapter is owned by the Pro rosbag feature.
    @Published var isReplayActive: Bool = false
    /// URL of the currently loaded rosbag file (for UI display).
    @Published var replayBagURL: URL?
    /// Bumped every time a new replay session starts. Observers use this instead
    /// of an equality check so a second file drop always triggers a load.
    @Published var replaySessionID: UUID = UUID()

    // MARK: - Logs (/rosout)
    @Published var activeLogStore: LogStore?

    // MARK: - Robot model
    @Published var activeRobotModel: RobotModel?
    @Published var activeRobotMeshes: [String: LoadedMesh] = [:]
    @Published var robotModelWarnings: [String] = []
    @Published var userMeshRoot: URL? {
        didSet {
            if let url = userMeshRoot {
                UserDefaults.standard.set(url.path, forKey: "userMeshRoot")
            } else {
                UserDefaults.standard.removeObject(forKey: "userMeshRoot")
            }
        }
    }

    // MARK: - Fixed frame
    @Published var availableFrames: [String] = []
    @Published var fixedFrame: String = "odom" {
        didSet {
            guard oldValue != fixedFrame else { return }
            UserDefaults.standard.set(fixedFrame, forKey: "defaultFixedFrame")
            saveViewer3DConfig()
            NotificationCenter.default.post(
                name: NSNotification.Name("com.jatupon.ros2studio.fixedFrameChanged"),
                object: fixedFrame)
            toasts.show(.info, title: "Fixed frame: \(fixedFrame)", autoDismiss: 1.5)
        }
    }

    // MARK: - Publish (write-path)
    @Published var activePublishService: PublishService?
    @Published var serverSupportsPublish: Bool = false

    // MARK: - Service Call
    @Published var activeServiceCallService: ServiceCallService?
    @Published var serviceCallViewModel: ServiceCallViewModel?

    // MARK: - Active connection handles (drives ConnectionView sidebar list)
    @Published public var activeConnectionHandles: [ConnectionHandle] = []

    // MARK: - 3D viewer state (lifted from Viewer3DView for per-profile persistence)

    /// Layers currently shown in the 3D viewer. Persisted per profile.
    @Published var viewer3DLayers: [DisplayLayer] = []

    /// The profile ID whose config is currently loaded. Used to key saves.
    private var activeProfileID: String? = nil

    private var observationTask: Task<Void, Never>?
    private var frameRefreshTask: Task<Void, Never>?
    private var robotDescriptionTask: Task<Void, Never>?
    private var tfSubscriptionTask: Task<Void, Never>?
    private var sharedMetalContext: MetalContext?
    private var layersSaveCancellable: AnyCancellable?

    init() {
        let logger = Logger(subsystem: "app.ros2studio", category: "app")
        self.logger = logger

        let registry = DefaultMessageRegistry(logger: logger)
        registry.freeze()
        self.registry = registry

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ROS2Studio", isDirectory: true)
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)

        let profilesURL = appSupport.appendingPathComponent("profiles.json")
        self.profileStore = ProfileStore(databaseURL: profilesURL, logger: logger)

        self.connectionManager = ConnectionManager(
            transportFactory: { _ in
                let ud = UserDefaults.standard
                let bufSize    = { let v = ud.integer(forKey: "perf.topicBufferSize");       return v > 0 ? v : 256 }()
                let reconnects = { let v = ud.integer(forKey: "perf.maxReconnectAttempts");  return v > 0 ? v : 10  }()
                let throttleMs = ud.integer(forKey: "perf.subscribeThrottleMs")
                return RosbridgeTransport(config: TransportConfig(
                    maxReconnectAttempts: reconnects,
                    topicBufferSize: bufSize,
                    subscribeThrottleMs: throttleMs))
            },
            logger: logger
        )

        let layoutURL = appSupport.appendingPathComponent("Layouts", isDirectory: true)
        try? FileManager.default.createDirectory(at: layoutURL, withIntermediateDirectories: true)
        self.layoutEngine = LayoutEngine(localURL: layoutURL, logger: logger)

        // Restore persisted prefs
        if let frame = UserDefaults.standard.string(forKey: "defaultFixedFrame") {
            self.fixedFrame = frame
        }
        if let meshPath = UserDefaults.standard.string(forKey: "userMeshRoot") {
            self.userMeshRoot = URL(fileURLWithPath: meshPath)
        }

        recentConnections = recentConnectionsStore.entries

        // Auto-save layers whenever they change (throttled slightly to avoid hammering
        // UserDefaults on rapid reorder/toggle).
        layersSaveCancellable = $viewer3DLayers
            .dropFirst()
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.saveViewer3DConfig()
            }
    }

    private func metalContext() -> MetalContext? {
        if let ctx = sharedMetalContext { return ctx }
        let ctx = try? MetalContext()
        sharedMetalContext = ctx
        return ctx
    }

    /// Begin observing ConnectionManager's connections stream.
    /// Call once from the root view's .task modifier.
    func startObservingConnections() async {
        for await handles in await connectionManager.connections {
            self.activeConnectionHandles = handles
            if let first = handles.first {
                // Record each newly connected robot in recent history
                recentConnectionsStore.record(name: first.profile.name, url: first.profile.url)
                recentConnections = recentConnectionsStore.entries
                let cacheCapacity = { let v = UserDefaults.standard.integer(forKey: "perf.topicCacheCapacity"); return v > 0 ? v : 1024 }()
                let tfHistorySec  = { let v = UserDefaults.standard.double(forKey: "perf.tfHistoryDurationSec");  return v > 0 ? v : 10.0 }()
                let store = TopicStore(transport: first.transport, registry: registry, cacheCapacity: cacheCapacity)
                let tfTree = TFTree(historyDuration: tfHistorySec)
                activeTopicStore = store
                activeTFTree = tfTree
                isReplayActive = false
                sessionMode = .live

                // Load per-profile 3D viewer config (layers + camera + fixed frame).
                // Key by name+URL (not .id) because ConnectionProfile gets a fresh UUID on
                // every connect call — the name+URL pair is stable for the same saved profile.
                let profileID = "\(first.profile.name)|\(first.profile.url.absoluteString)"
                activeProfileID = profileID
                if let saved = Viewer3DProfileConfig.load(for: profileID) {
                    viewer3DLayers = saved.layers
                    // Restore fixed frame from profile config only if not overridden globally.
                    if !saved.fixedFrame.isEmpty {
                        fixedFrame = saved.fixedFrame
                    }
                    // savedCameraData is passed to Viewer3DView at render time
                } else {
                    // No saved config — start with zero layers (ticket requirement).
                    viewer3DLayers = []
                }

                // Logs
                let logCap = { let v = UserDefaults.standard.integer(forKey: "perf.logCapacity"); return v > 0 ? v : 5000 }()
                let logs = LogStore(topicStore: store, capacity: logCap)
                activeLogStore = logs
                await logs.start()

                // Publish service + capability check
                let publish = PublishService(transport: first.transport)
                activePublishService = publish
                let caps = await first.transport.serverCapabilities()
                serverSupportsPublish = caps.contains("clientPublish")

                // Service Call
                let serviceCallSvc = ServiceCallService(transport: first.transport)
                activeServiceCallService = serviceCallSvc
                let scvm = ServiceCallViewModel(service: serviceCallSvc)
                serviceCallViewModel = scvm
                scvm.refreshServices()

                // Discover point-cloud and laser-scan topics from live session
                if let topics = try? await store.availableTopics() {
                    availableTopics = topics
                    activePointCloudTopics = topics
                        .filter { $0.schemaName.contains("PointCloud") }
                        .map { $0.name }
                    activeLaserScanTopics = topics
                        .filter { $0.schemaName.contains("LaserScan") }
                        .map { $0.name }
                    // Notify Pro features (Plot, Recording, …) that a live session started.
                    ProUIRegistry.shared.notifySessionDidStart(store: store, topics: availableTopics, mode: .live)
                }

                // Restore a previously saved URDF file — persists per connection profile
                // across restarts. If a saved file exists, it takes priority over
                // /robot_description so the user's explicit choice is never overwritten.
                let saved = Viewer3DProfileConfig.load(for: profileID)
                let hasSavedURDF: Bool
                if let savedURL = saved?.urdfFileURL, FileManager.default.fileExists(atPath: savedURL.path) {
                    hasSavedURDF = true
                    Task { [weak self] in
                        _ = await self?.restoreURDFFile(url: savedURL)
                    }
                } else {
                    hasSavedURDF = false
                }

                // Watch /robot_description only when no saved URDF file exists.
                if !hasSavedURDF, availableTopics.contains(where: { $0.name == "/robot_description" }) {
                    startRobotDescriptionWatch(store: store)
                }

                // Feed /tf and /tf_static into the TFTree actor
                startTFSubscription(store: store, tfTree: tfTree)

                // Refresh available frames periodically while connected
                startFrameRefresh(tfTree: tfTree)
            } else {
                if !isReplayActive {
                    tearDownSession()
                }
            }
        }
    }

    /// Save the current 3D viewer layers + fixed frame to the active profile's config.
    /// Camera data is saved via the `onCameraChanged` callback in Viewer3DView.
    func saveViewer3DConfig(cameraData: Data? = nil) {
        guard let profileID = activeProfileID else { return }
        // Merge any provided camera data and URDF URL with what's already saved.
        let existing = Viewer3DProfileConfig.load(for: profileID)
        let config = Viewer3DProfileConfig(
            layers: viewer3DLayers,
            cameraData: cameraData ?? existing?.cameraData,
            fixedFrame: fixedFrame,
            urdfFileURL: existing?.urdfFileURL
        )
        config.save(for: profileID)
    }

    /// Called by Viewer3DView's onCameraChanged callback to persist camera immediately.
    func saveCameraData(_ data: Data) {
        guard let profileID = activeProfileID else { return }
        let existing = Viewer3DProfileConfig.load(for: profileID)
        let config = Viewer3DProfileConfig(
            layers: existing?.layers ?? viewer3DLayers,
            cameraData: data,
            fixedFrame: fixedFrame,
            urdfFileURL: existing?.urdfFileURL
        )
        config.save(for: profileID)
    }

    /// Returns the saved camera data for the active profile (to seed Viewer3DView on connect).
    var savedCameraDataForActiveProfile: Data? {
        guard let profileID = activeProfileID else { return nil }
        return Viewer3DProfileConfig.load(for: profileID)?.cameraData
    }

    private func tearDownSession() {
        // Persist current 3D viewer config before clearing state.
        saveViewer3DConfig()
        replayBagURL = nil

        // Notify Pro features (Plot, Recording, …) that the session is ending.
        // The Recording feature stops any active recording via this callback.
        ProUIRegistry.shared.notifySessionWillEnd()
        isReplayActive = false

        Task { [logs = activeLogStore] in await logs?.stop() }
        Task { [publish = activePublishService] in await publish?.reset() }
        activeServiceCallService = nil
        serviceCallViewModel = nil
        activeTopicStore = nil
        activeTFTree = nil
        activePointCloudTopics = []
        activeLaserScanTopics = []
        availableTopics = []
        activeLogStore = nil
        activeRobotModel = nil
        activeRobotMeshes = [:]
        robotModelWarnings = []
        availableFrames = []
        activePublishService = nil
        serverSupportsPublish = false
        activeConnectionHandles = []
        activeProfileID = nil
        viewer3DLayers = []
        frameRefreshTask?.cancel(); frameRefreshTask = nil
        robotDescriptionTask?.cancel(); robotDescriptionTask = nil
        tfSubscriptionTask?.cancel(); tfSubscriptionTask = nil
    }

    func disconnectAll() async {
        let handles = await connectionManager.activeHandles
        let hadConnections = !handles.isEmpty || activeTopicStore != nil
        for handle in handles {
            try? await connectionManager.disconnect(handle)
        }
        // Also tear down replay sessions which don't go through ConnectionManager.
        if activeTopicStore != nil {
            tearDownSession()
            selection.select(nil)
        }
        if hadConnections {
            toasts.show(.success, title: "Disconnected")
        }
    }

    // MARK: - Mode switching

    /// Switch the top-level session mode. Tears down any active session in the
    /// previous mode and transitions to the new mode's initial state.
    func setMode(_ mode: SessionMode) {
        guard mode != sessionMode else { return }
        sessionMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: "lastSessionMode")

        switch mode {
        case .live:
            if activeTopicStore != nil {
                tearDownSession()
                selection.select(nil)
            }
            toasts.show(.info, title: "Live Mode",
                        message: "Connect to a ROS2 robot via rosbridge.")

        case .replay:
            Task { await disconnectAll() }
        }
    }

    // MARK: - Frame refresh

    private func startFrameRefresh(tfTree: TFTree) {
        frameRefreshTask?.cancel()
        frameRefreshTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let frames = await tfTree.frames()
                await self.applyFrames(frames)
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func applyFrames(_ frames: [String]) {
        availableFrames = frames
        if !frames.isEmpty, !frames.contains(fixedFrame) {
            fixedFrame = frames.contains("map") ? "map" : (frames.contains("odom") ? "odom" : (frames.first ?? "odom"))
        }
    }

    // MARK: - TF subscription

    private func startTFSubscription(store: TopicStore, tfTree: TFTree) {
        tfSubscriptionTask?.cancel()
        tfSubscriptionTask = Task { [weak self] in
            guard self != nil else { return }  // keep app alive check
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await Self.feedTF(store: store, tfTree: tfTree, topic: "/tf", isStatic: false) }
                group.addTask { await Self.feedTF(store: store, tfTree: tfTree, topic: "/tf_static", isStatic: true) }
            }
        }
    }

    private static func feedTF(store: TopicStore, tfTree: TFTree, topic: String, isStatic: Bool) async {
        guard let stream = try? await store.subscribePayload(topic) else { return }
        for await stamped in stream {
            guard let msg = try? JSONDecoder().decode(TFMessagePayload.self, from: stamped.value) else { continue }
            for xf in msg.transforms {
                let stamp = UInt64(xf.header.stamp.sec) * 1_000_000_000 + UInt64(xf.header.stamp.nanosec)
                let t = xf.transform
                await tfTree.insert(
                    parent: xf.header.frame_id,
                    child: xf.child_frame_id,
                    transform: TFTransform(
                        translation: SIMD3(t.translation.x, t.translation.y, t.translation.z),
                        rotation: simd_quatd(ix: t.rotation.x, iy: t.rotation.y, iz: t.rotation.z, r: t.rotation.w)),
                    at: stamp,
                    isStatic: isStatic)
            }
        }
    }

    // MARK: - Robot description (URDF)

    private func startRobotDescriptionWatch(store: TopicStore) {
        robotDescriptionTask?.cancel()
        robotDescriptionTask = Task { [weak self] in
            guard let self else { return }
            do {
                let stream = try await store.subscribePayload("/robot_description")
                for await stamped in stream {
                    // rosbridge wraps std_msgs/String as {"data": "<xml...>"}.
                    // Try that first; fall back to treating the whole payload as raw XML.
                    let xml: String
                    if let obj = try? JSONSerialization.jsonObject(with: stamped.value) as? [String: Any],
                       let inner = obj["data"] as? String {
                        xml = inner
                    } else if let raw = String(data: stamped.value, encoding: .utf8) {
                        xml = raw
                    } else {
                        continue
                    }
                    await self.loadURDFXML(xml, baseURL: nil)
                    return // first description wins
                }
            } catch { /* /robot_description not advertised */ }
        }
    }

    /// Load and parse a URDF XML string into the active robot model. Off-main parse,
    /// main-actor publish of results.
    func loadURDFXML(_ xml: String, baseURL: URL?) async {
        guard let ctx = metalContext() else { return }
        let loader = RobotModelLoader(context: ctx)
        let meshRoot = userMeshRoot
        do {
            let result = try loader.loadFromURDF(
                xml: xml,
                baseURL: baseURL,
                packagePaths: [:],
                meshRoot: meshRoot)
            activeRobotModel = result.model
            activeRobotMeshes = result.meshes
            robotModelWarnings = result.warnings
            if result.meshes.isEmpty && !result.warnings.isEmpty {
                toasts.show(.warning, title: "Robot model: mesh paths unresolved",
                            message: result.warnings.first ?? "Set a mesh folder in Settings to load 3D geometry")
            } else {
                toasts.show(.success, title: "Robot model loaded",
                            message: "\(result.model.links.count) links, \(result.meshes.count) meshes")
            }
        } catch {
            robotModelWarnings = ["URDF parse failed: \(error.localizedDescription)"]
            toasts.show(.error, title: "URDF parse failed", message: error.localizedDescription)
        }
    }

    /// Persist the given URDF file URL to the active profile so it survives reconnect.
    func saveURDFProfile(url: URL?) {
        guard let profileID = activeProfileID else { return }
        let existing = Viewer3DProfileConfig.load(for: profileID)
        let config = Viewer3DProfileConfig(
            layers: existing?.layers ?? viewer3DLayers,
            cameraData: existing?.cameraData,
            fixedFrame: existing?.fixedFrame ?? fixedFrame,
            urdfFileURL: url
        )
        config.save(for: profileID)
    }

    /// Load a URDF file from disk. Used by the "Load URDF…" menu item.
    /// Automatically persists the URL to the active profile for reconnect.
    func loadURDFFile(_ url: URL) async throws -> RobotModelLoader.RobotModelSummary {
        guard let ctx = metalContext() else {
            throw NSError(domain: "AppServices", code: 1, userInfo: [NSLocalizedDescriptionKey: "Metal context unavailable"])
        }
        let loader = RobotModelLoader(context: ctx)
        let result = try loader.loadFromFile(url, packagePaths: [:], meshRoot: userMeshRoot)
        activeRobotModel = result.model
        activeRobotMeshes = result.meshes
        robotModelWarnings = result.warnings
        if result.meshes.isEmpty && !result.warnings.isEmpty {
            toasts.show(.warning, title: "Meshes not found",
                        message: result.warnings.first ?? "Place mesh files next to the URDF or set a mesh folder in Settings")
        }
        saveURDFProfile(url: url)
        return result.summary
    }

    /// Load a saved URDF file silently on reconnect — no toasts on success.
    @discardableResult
    func restoreURDFFile(url: URL) async -> Bool {
        guard let ctx = metalContext() else { return false }
        let loader = RobotModelLoader(context: ctx)
        do {
            let result = try loader.loadFromFile(url, packagePaths: [:], meshRoot: userMeshRoot)
            activeRobotModel = result.model
            activeRobotMeshes = result.meshes
            robotModelWarnings = result.warnings
            // Only toast on warnings — success is silent during restoration.
            if result.meshes.isEmpty && !result.warnings.isEmpty {
                toasts.show(.warning, title: "Meshes not found",
                            message: result.warnings.first ?? "Set a mesh folder in Settings")
            }
            return true
        } catch {
            robotModelWarnings = ["Restored URDF failed: \(error.localizedDescription)"]
            saveURDFProfile(url: nil)
            toasts.show(.error, title: "Restored URDF failed",
                        message: "The saved URDF file could not be loaded. It has been removed from the profile. \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Focus new connection (menu/toolbar command → ConnectionView observes)

    func focusNewConnection() {
        NotificationCenter.default.post(
            name: Notification.Name("com.jatupon.ros2studio.focusNewConnection"),
            object: nil)
    }

    // MARK: - Reset camera (menu command → Viewer3DView observes)

    func resetCameraFromMenu() {
        NotificationCenter.default.post(name: Notification.Name("com.jatupon.ros2studio.resetCamera"), object: nil)
    }

    // MARK: - Replay session install (transport-agnostic; core)

    /// Installs an already-connected replay transport as the active session.
    /// The concrete MCAP adapter is created by the Pro rosbag feature and passed
    /// in here as a plain `TransportClient`, so this method stays Pro-free.
    public func beginReplaySession(transport: any TransportClient, bagURL: URL) async throws {
        // Disconnect any active live connections
        let handles = await connectionManager.activeHandles
        for handle in handles {
            try? await connectionManager.disconnect(handle)
        }

        // Clean up any existing session
        tearDownSession()

        let cacheCapacity = { let v = UserDefaults.standard.integer(forKey: "perf.topicCacheCapacity"); return v > 0 ? v : 1024 }()
        let tfHistorySec  = { let v = UserDefaults.standard.double(forKey: "perf.tfHistoryDurationSec");  return v > 0 ? v : 10.0 }()
        let store = TopicStore(transport: transport, registry: registry, cacheCapacity: cacheCapacity)
        let tfTree = TFTree(historyDuration: tfHistorySec)
        let topics = (try? await store.availableTopics()) ?? []
        isReplayActive = true
        replaySessionID = UUID()  // bump so MainWindow's .onChange fires for every new load
        activeTopicStore = store
        activeTFTree = tfTree
        availableTopics = topics
        activePointCloudTopics = topics.filter { $0.schemaName.contains("PointCloud") }.map { $0.name }
        activeLaserScanTopics  = topics.filter { $0.schemaName.contains("LaserScan") }.map  { $0.name }
        replayBagURL = bagURL

        // Clear profile tracking so replay doesn't corrupt any live profile's saved config.
        activeProfileID = nil
        viewer3DLayers = []

        // Notify Pro features (Plot, …) that a replay session started.
        ProUIRegistry.shared.notifySessionDidStart(store: store, topics: topics, mode: .replay)

        // Watch /robot_description
        if topics.contains(where: { $0.name == "/robot_description" }) {
            startRobotDescriptionWatch(store: store)
        }

        // Feed /tf and /tf_static into the TFTree actor
        startTFSubscription(store: store, tfTree: tfTree)

        // Refresh available frames periodically while connected
        startFrameRefresh(tfTree: tfTree)

        // Logs
        let logCap = { let v = UserDefaults.standard.integer(forKey: "perf.logCapacity"); return v > 0 ? v : 5000 }()
        let logs = LogStore(topicStore: store, capacity: logCap)
        activeLogStore = logs
        await logs.start()

        sessionMode = .replay
    }

}

// MARK: - tf2_msgs/msg/TFMessage Codable (rosbridge JSON wire format)

private struct TFMessagePayload: Decodable {
    let transforms: [TransformStamped]
}

private struct TransformStamped: Decodable {
    let header: Header
    let child_frame_id: String
    let transform: RosTransform
}

private struct Header: Decodable {
    let stamp: RosStamp
    let frame_id: String
}

private struct RosStamp: Decodable {
    let sec: Int64
    let nanosec: UInt32
}

private struct RosTransform: Decodable {
    let translation: RosVector3
    let rotation: RosQuaternion
}

private struct RosVector3: Decodable {
    let x: Double
    let y: Double
    let z: Double
}

private struct RosQuaternion: Decodable {
    let x: Double
    let y: Double
    let z: Double
    let w: Double
}
