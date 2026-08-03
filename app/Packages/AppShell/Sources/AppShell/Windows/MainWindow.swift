import AppKit
import SwiftUI
import UniformTypeIdentifiers
import Transport
import TopicStore
import TFTree
import ConnectionUI
import TopicBrowserUI
import InspectorUI
import Viewer3DUI
import ConnectionManager
import ProfileStore
import LogViewerUI
import LogStore
import PublishUI
import PublishService
import MetalCore
import RobotModelRenderer
import MeshLoader
import ServiceCallService
import ServiceCallUI

/// Two-column layout: 3D Viewer | Inspector (with topic picker)
/// Connection management lives in a top-center toolbar control (Xcode scheme-selector style).
struct MainWindow: View {
    @EnvironmentObject var services: AppServices

    var body: some View {
        MainWindowBody(
            services: services,
            selection: services.selection,
            toasts: services.toasts
        )
    }
}

private enum RightPanelTab: String, CaseIterable {
    case inspector = "Inspector"
    case parameters = "Parameters"
    case tfTree = "TF Tree"
    case monitor = "Monitor"
    case plot = "Plot"
    case services = "Services"

    var displayName: String {
        switch self {
        case .inspector:  return "Inspector"
        case .parameters: return "Parameters"
        case .tfTree:     return "TF Tree"
        case .monitor:    return "Monitor"
        case .plot:       return "Plot"
        case .services:   return "Services"
        }
    }

    /// Stable identifier used to look up injected Pro content in `ProUIRegistry`.
    var id: String {
        switch self {
        case .inspector:  return RightPanelTabID.inspector
        case .parameters: return RightPanelTabID.parameters
        case .tfTree:     return RightPanelTabID.tfTree
        case .monitor:    return RightPanelTabID.monitor
        case .plot:       return RightPanelTabID.plot
        case .services:   return RightPanelTabID.services
        }
    }

    /// Tabs whose content is supplied by a Pro plugin. They only appear when the
    /// corresponding builder is registered (i.e. in the paid build).
    var isProInjected: Bool {
        self == .parameters || self == .plot
    }

    @MainActor
    static func allCases(for mode: SessionMode) -> [RightPanelTab] {
        let base: [RightPanelTab]
        switch mode {
        case .live:   base = [.inspector, .parameters, .tfTree, .monitor, .plot, .services]
        case .replay: base = [.inspector, .tfTree, .monitor, .plot]
        }
        return base.filter { tab in
            tab.isProInjected ? ProUIRegistry.shared.hasPanel(id: tab.id) : true
        }
    }
}

/// Eager viewModel host that creates a Viewer3DViewModel before its children render.
/// Avoids the race where Viewer3DView creates an internal viewModel while the parent
/// lazily creates the shared one via .task — this was causing layers added via the
/// separated LayersPanel to not render in the 3D viewport.
private struct _ConnectedView<Layers: View, Viewport: View, Log: View>: View {
    @State private var viewModel: Viewer3DViewModel
    let store: TopicStore
    let tfTree: TFTree
    let layers: (Viewer3DViewModel) -> Layers
    let viewport: (Viewer3DViewModel) -> Viewport
    let log: () -> Log

    init(
        store: TopicStore,
        tfTree: TFTree,
        @ViewBuilder layers: @escaping (Viewer3DViewModel) -> Layers,
        @ViewBuilder viewport: @escaping (Viewer3DViewModel) -> Viewport,
        @ViewBuilder log: @escaping () -> Log
    ) {
        self.store = store
        self.tfTree = tfTree
        self.layers = layers
        self.viewport = viewport
        self.log = log
        self._viewModel = State(initialValue: Viewer3DViewModel(store: store, tfTree: tfTree))
    }

    var body: some View {
        HStack(spacing: 0) {
            layers(viewModel)
                .frame(width: 276)
            Divider()
            VSplitView {
                viewport(viewModel)
                    .frame(minHeight: 120, idealHeight: 700, maxHeight: .infinity)
                log()
                    .frame(minHeight: 80, idealHeight: 140, maxHeight: 280)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onDisappear {
            viewModel.stopSubscriptions()
        }
    }
}

private struct MainWindowBody: View {
    @ObservedObject var services: AppServices
    @ObservedObject var selection: SelectionStore
    @ObservedObject var toasts: ToastCenter
    @Environment(PerformanceStore.self) private var performance
    @Environment(PerformanceDashboard.self) private var dashboard
    @State private var showingMeshFolderPicker = false
    @State private var showPerfPanel = false
    @State private var selectedRightTab: RightPanelTab = .inspector
    @State private var showPublishSheet = false
    @State private var selectedFrameName: String?
    @State private var tfUniverseMode: Bool = false
    @StateObject private var publishFormState = PublishFormState()
    /// Controls the "New Connection" sheet triggered by the toolbar connection control.
    @State private var showingNewConnectionSheet = false
    @State private var showBagManager = false
    /// Tracks whether the popover topic picker is open in the Inspector panel.
    @State private var showTopicPicker = false
    private var selectionBinding: Binding<TopicDescriptor?> {
        Binding(get: { selection.selected },
                set: { selection.select($0) })
    }

    private var fixedFrameBinding: Binding<String> {
        Binding(get: { services.fixedFrame },
                set: { services.fixedFrame = $0 })
    }

    @ViewBuilder
    private var toastOverlay: some View {
        ToastStack(center: services.toasts)
            .allowsHitTesting(true)
    }

    @ViewBuilder
    private var replayBottomBar: some View {
        if services.sessionMode == .replay {
            if let bar = ProUIRegistry.shared.makeReplayBar(services: services) {
                bar
            }
        }
    }

    private var layoutBody: some View {
        Color.clear
            .overlay {
                HSplitView {
                    viewerContent
                        .frame(minWidth: 480, idealWidth: 800, maxWidth: .infinity, maxHeight: .infinity)
                    inspectorContent
                        .overlay(alignment: .leading) {
                            Rectangle()
                                .fill(Color(red: 0x2A / 255.0, green: 0x2D / 255.0, blue: 0x32 / 255.0))
                                .frame(width: 1)
                        }
                        .frame(minWidth: 320, idealWidth: 360, maxWidth: 560, maxHeight: .infinity)
                }
            }
    }

    private var handlersPart1: some View {
        layoutBody
            .onChange(of: services.sessionMode) { _, newMode in
            if newMode == .replay, (selectedRightTab == .parameters || selectedRightTab == .services) {
                selectedRightTab = .inspector
            }
            if newMode == .live, services.activeConnectionHandles.isEmpty {
                showingNewConnectionSheet = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("com.jatupon.ros2studio.openPanel"))) { notif in
            guard let panel = notif.object as? String else { return }
            switch panel {
            case "logs": break
            case "tf_tree", "tf":
                selectedRightTab = .tfTree
                let tfTopics = services.availableTopics.filter { $0.schemaName.contains("tf2_msgs") && $0.schemaName.contains("TFMessage") }
                if let tfTopic = tfTopics.first(where: { $0.name == "/tf" }) ?? tfTopics.first {
                    services.selection.select(tfTopic)
                }
            case "rosbag": openRosbagPanel()
            case "inspector":
                selectedRightTab = .inspector
            case "parameters":
                selectedRightTab = .parameters
            case "monitor":
                selectedRightTab = .monitor
            case "publish":
                showPublishSheet = true
            case "3d_viewer": break
            default: break
            }
        }
        .onReceive(NotificationCenter.default.publisher(
            for: Notification.Name("com.jatupon.ros2studio.focusNewConnection")
        )) { _ in
            if services.sessionMode == .replay {
                services.setMode(.live)
            }
            showingNewConnectionSheet = true
        }
    }

    private var handlersPart2: some View {
        handlersPart1
        .onReceive(NotificationCenter.default.publisher(
            for: Notification.Name("com.jatupon.ros2studio.openRosbag")
        )) { _ in
            if services.sessionMode == .live {
                services.setMode(.replay)
            }
            openRosbagPanel()
        }
        .onReceive(NotificationCenter.default.publisher(
            for: Notification.Name("com.jatupon.ros2studio.tfUniverseRequested"))) { _ in
            selectedRightTab = .tfTree
            withAnimation(.easeInOut(duration: 0.3)) {
                tfUniverseMode = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(
            for: Notification.Name("com.jatupon.ros2studio.tfUniverseExit"))) { _ in
            withAnimation(.easeInOut(duration: 0.3)) {
                tfUniverseMode = false
            }
        }
    }

    private var mainBodyWithHandlers: some View {
        handlersPart2
        .onReceive(NotificationCenter.default.publisher(for: .frameInspectorClear)) { _ in
            selectedFrameName = nil
        }
        .onReceive(NotificationCenter.default.publisher(
            for: Notification.Name("com.jatupon.ros2studio.openBagManager")
        )) { _ in
            showBagManager = true
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("com.jatupon.ros2studio.publishResult"))) { notif in
            guard let info = notif.userInfo else { return }
            let success = info["success"] as? Bool ?? false
            if success, let topic = info["topic"] as? String {
                services.toasts.show(.success, title: "Published to \(topic)")
            } else if let error = info["error"] as? String {
                services.toasts.show(.error, title: "Publish failed", message: error)
            }
        }
    }

    private var mainBody: some View {
        mainBodyWithHandlers
        .fileImporter(
            isPresented: $showingMeshFolderPicker,
            allowedContentTypes: [.folder]
        ) { result in
            if case .success(let url) = result {
                services.userMeshRoot = url
                services.toasts.show(.info, title: "Mesh folder set", message: url.lastPathComponent)
            }
        }
        .sheet(isPresented: $showBagManager) {
            let host = services.activeConnectionHandles.first?.profile.url.host ?? "localhost"
            if let manager = ProUIRegistry.shared.makeBagManager(
                host: host, services: services, onDismiss: { showBagManager = false }) {
                manager
            }
        }
        .sheet(isPresented: $showPublishSheet) {
            let ctx = PublishSheetContext(
                publishService: services.activePublishService,
                topics: services.availableTopics,
                isEnabled: services.serverSupportsPublish,
                formState: publishFormState
            )
            if let sheet = ProUIRegistry.shared.makePublishSheet(context: ctx) {
                sheet
            } else {
                // Free (Community) build: basic publishing is a Core feature —
                // the template-free publish form, no templates sidebar.
                CorePublishSheet(
                    publishService: services.activePublishService,
                    topics: services.availableTopics,
                    isEnabled: services.serverSupportsPublish,
                    formState: publishFormState)
            }
        }
        .sheet(isPresented: $showingNewConnectionSheet) {
            NewConnectionSheetHost(
                connectionManager: services.connectionManager,
                profileStore: services.profileStore,
                onConnectResult: { ok, info in
                    if ok {
                        services.toasts.show(.success, title: "Connected", message: info)
                        showingNewConnectionSheet = false
                    } else {
                        services.toasts.show(.error, title: "Could not connect", message: info)
                    }
                },
                onSave: { name in
                    services.toasts.show(.success, title: "Profile saved", message: name)
                }
            )
        }
    }

    var body: some View {
        mainBody
            .overlay(alignment: .bottom) {
                if showPerfPanel {
                    PerformancePanelView(isPresented: $showPerfPanel)
                        .environmentObject(services)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .toolbar { toolbarItems }
            .overlay(alignment: .topTrailing) { toastOverlay }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    replayBottomBar
                    PerformanceFooterBar(showPanel: $showPerfPanel)
                }
            }
            .task {
                dashboard.services = services
            }
    }

    // MARK: - Rosbag file picker

    private func openRosbagPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "mcap") ?? .data]
        panel.allowsMultipleSelection = false
        panel.title = "Open Rosbag (MCAP)"
        panel.beginSheetModal(for: NSApp.keyWindow ?? NSWindow()) { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in await loadReplaySession(from: url) }
        }
    }

    @MainActor
    private func loadReplaySession(from url: URL) async {
        // Delegates to the Pro rosbag feature (creates the MCAP adapter, installs
        // the session, and wires the player). No-op in a build without the feature.
        await ProUIRegistry.shared.openReplay(url: url, services: services)
    }

    // MARK: - 3D Viewer

    private var viewer3DLayersBinding: Binding<[DisplayLayer]> {
        Binding(
            get: { services.viewer3DLayers },
            set: { services.viewer3DLayers = $0 }
        )
    }

    @ViewBuilder
    private var viewerContent: some View {
        if let store = services.activeTopicStore,
           let tfTree = services.activeTFTree {
            _ConnectedView(
                store: store,
                tfTree: tfTree,
                layers: { vm in layersContent(viewModel: vm) },
                viewport: { vm in viewer3DPanel(store: store, tfTree: tfTree, externalViewModel: vm) },
                log: {
                    if let logs = services.activeLogStore {
                        LogViewerView(store: logs)
                    } else {
                        ContentUnavailableView(
                            "No logs yet",
                            systemImage: "doc.text.magnifyingglass",
                            description: Text(
                                services.sessionMode == .replay
                                    ? "Open an MCAP rosbag file containing /rosout messages."
                                    : "Connect to a robot to see live /rosout messages."
                            )
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(red: 0x1D / 255.0, green: 0x1F / 255.0, blue: 0x24 / 255.0))
                    }
                }
            )
            .id("viewer3D-\(services.activeConnectionHandles.count)")
        } else {
            logSplitPane(store: nil, tfTree: nil, logs: nil)
        }
    }

    @ViewBuilder
    private func layersContent(viewModel vm: Viewer3DViewModel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            LayersPanel(
                layers: viewer3DLayersBinding,
                availableTopics: services.availableTopics,
                onLoadURDF: { [weak services] in
                    guard let services else { return }
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [.xml, UTType(filenameExtension: "urdf") ?? .xml]
                    panel.allowsMultipleSelection = false
                    panel.canChooseDirectories = false
                    panel.title = "Select Robot URDF File"
                    panel.beginSheetModal(for: NSApp.keyWindow ?? NSWindow()) { response in
                        guard response == .OK, let url = panel.url else { return }
                        Task {
                            do {
                                _ = try await services.loadURDFFile(url)
                                services.toasts.show(.success, title: "URDF loaded", message: url.lastPathComponent)
                                if !services.viewer3DLayers.contains(where: { $0.type == .robotModel }) {
                                    services.viewer3DLayers.append(DisplayLayer(topic: "", type: .robotModel))
                                }
                                NotificationCenter.default.post(
                                    name: Notification.Name("com.jatupon.ros2studio.resetCamera"),
                                    object: nil)
                            } catch {
                                services.toasts.show(.error, title: "Load URDF failed", message: error.localizedDescription)
                            }
                        }
                    }
                },
                onLoadStaticMap: { [weak services] in
                    guard let services else { return }
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [.yaml, UTType(filenameExtension: "yaml") ?? .yaml]
                    panel.allowsMultipleSelection = false
                    panel.canChooseDirectories = false
                    panel.title = "Select Static Map File (.yaml)"
                    panel.beginSheetModal(for: NSApp.keyWindow ?? NSWindow()) { response in
                        guard response == .OK, let yamlURL = panel.url else { return }
                        let pgmURL = yamlURL.deletingPathExtension().appendingPathExtension("pgm")
                        guard FileManager.default.fileExists(atPath: pgmURL.path) else {
                            services.toasts.show(.error, title: "Map file not found", message: "Expected \(pgmURL.lastPathComponent) next to \(yamlURL.lastPathComponent)")
                            return
                        }
                        let layerID = UUID()
                        FileLoadRegistry.shared.registerStaticMap(layerID: layerID, yamlURL: yamlURL, pgmURL: pgmURL)
                        services.viewer3DLayers.append(DisplayLayer(topic: yamlURL.deletingPathExtension().lastPathComponent, type: .staticMap, layerID: layerID))
                        services.toasts.show(.success, title: "Static map added", message: yamlURL.lastPathComponent)
                    }
                },
                onLoadMeshMap: { [weak services] in
                    guard let services else { return }
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [
                        UTType(filenameExtension: "ply") ?? .data,
                        UTType(filenameExtension: "obj") ?? .data
                    ]
                    panel.allowsMultipleSelection = false
                    panel.canChooseDirectories = false
                    panel.title = "Select Mesh Map File (.ply / .obj)"
                    panel.beginSheetModal(for: NSApp.keyWindow ?? NSWindow()) { response in
                        guard response == .OK, let fileURL = panel.url else { return }
                        let layerID = UUID()
                        FileLoadRegistry.shared.registerMeshMap(layerID: layerID, fileURL: fileURL)
                        services.viewer3DLayers.append(DisplayLayer(topic: fileURL.deletingPathExtension().lastPathComponent, type: .meshMap, layerID: layerID))
                        services.toasts.show(.success, title: "Mesh map added", message: fileURL.lastPathComponent)
                    }
                },
                robotModel: services.activeRobotModel,
                loadedMeshKeys: Set(services.activeRobotMeshes.keys),
                onOverrideLinkMesh: { linkName, url in
                    guard let model = vm.robotModel,
                          let link = model.links.first(where: { $0.name == linkName }),
                          let meshKey = link.meshKey,
                          let rmr = vm.robotRenderer,
                          let ctx = vm.metalContext
                    else { return }
                    do {
                        let loaded = try MeshLoader(context: ctx).load(from: url)
                        rmr.overrideLinkMesh(meshKey: meshKey, with: loaded)
                    } catch {
                        // Path saved in settings; reload on next model set
                    }
                },
                viewModel: vm)
                .padding(8)
            Spacer()
        }
        .frame(maxHeight: .infinity)
        .background(.background)
    }

    @ViewBuilder
    private func viewer3DPanel(store: TopicStore, tfTree: TFTree, externalViewModel: Viewer3DViewModel? = nil) -> some View {
        Viewer3DView(
            store: store,
            tfTree: tfTree,
            robotModel: services.activeRobotModel,
            loadedMeshes: services.activeRobotMeshes,
            fixedFrame: services.fixedFrame,
            availableTopics: services.availableTopics,
            availableFrames: services.availableFrames,
            fixedFrameBinding: fixedFrameBinding,
            layersBinding: viewer3DLayersBinding,
            savedCameraData: services.savedCameraDataForActiveProfile,
            onCameraChanged: { [weak services] data in
                services?.saveCameraData(data)
            },
            publishService: services.activePublishService,
            onShowPublish: { showPublishSheet = true },
            onPoseEstimateSent: { [weak services] in
                services?.toasts.show(.success, title: "Pose estimate sent")
            },
            onFixedFrameAutoSwitched: { [weak services] frame in
                services?.toasts.show(.info, title: "Fixed frame set to '\(frame)' for pose estimate.")
            },
            selectedFrameName: $selectedFrameName,
            externalViewModel: externalViewModel,
            showLayersSidebar: false,
            tfUniverseMode: $tfUniverseMode,
            lodThreshold: performance.lodThreshold,
            renderFPS: performance.renderFPS,
            renderResolution: performance.renderResolution,
            onFrameDrawn: { [dashboard] in dashboard.recordFrame() })
    }

    @ViewBuilder
    private func logSplitPane(store: TopicStore?, tfTree: TFTree?, logs: LogStore?, externalViewModel: Viewer3DViewModel? = nil) -> some View {
        VSplitView {
            Group {
                if let store, let tfTree {
                    viewer3DPanel(store: store, tfTree: tfTree, externalViewModel: externalViewModel)
                } else {
                    notConnectedPlaceholder
                }
            }
            .frame(minHeight: 120, idealHeight: 700, maxHeight: .infinity)

            Group {
                if let logs {
                    LogViewerView(store: logs)
                } else {
                    ContentUnavailableView(
                        "No logs yet",
                        systemImage: "doc.text.magnifyingglass",
                        description: Text(
                            services.sessionMode == .replay
                                ? "Open an MCAP rosbag file containing /rosout messages."
                                : "Connect to a robot to see live /rosout messages."
                        )
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(red: 0x1D / 255.0, green: 0x1F / 255.0, blue: 0x24 / 255.0))
                }
            }
            .frame(minHeight: 80, idealHeight: 140, maxHeight: 280)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Inspector

    @ViewBuilder
    private var inspectorContent: some View {
        VStack(spacing: 0) {
            // Tab bar ALWAYS visible — orients the user regardless of connection state
            // Note: on macOS, Picker label suppression requires placing the Picker inside
            // a Form/LabeledContent or using an empty label. We use accessibilityLabel to
            // keep VoiceOver context while hiding the visual "Panel" text.
            HStack {
                Picker(selection: $selectedRightTab) {
                    ForEach(RightPanelTab.allCases(for: services.sessionMode), id: \.self) { tab in
                        Text(tab.displayName).tag(tab)
                    }
                } label: {
                    EmptyView()
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .help("Switch between Inspector, Parameters, and TF Tree")
                .accessibilityLabel("Panel")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Monitor tab is always available, regardless of connection state
            if selectedRightTab == .monitor {
                MonitoringView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let store = services.activeTopicStore {
                switch selectedRightTab {
                case .inspector:
                    // Topic picker only shown in Inspector tab — not shared across all tabs
                    topicPickerRow(store: store)

                    Divider()

                    if let topic = services.selection.selected {
                        InspectorView(
                            store: store,
                            registry: services.registry,
                            topic: topic,
                            tfTreeContent: {
                                TFTreeTabView(tfTree: services.activeTFTree, frames: services.availableFrames, selectedFrame: $selectedFrameName)
                            })
                            .id(topic.name)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        inspectorEmpty
                    }

                case .parameters:
                    proPanel(.parameters, store: store)

                case .tfTree:
                    if let tfTree = services.activeTFTree {
                        TFTreeTabView(tfTree: tfTree, frames: services.availableFrames, selectedFrame: $selectedFrameName)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ContentUnavailableView(
                            "No TF Data",
                            systemImage: "point.3.connected.trianglepath.dotted",
                            description: Text("Connect to a robot publishing /tf or /tf_static.")
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }

                case .monitor:
                    EmptyView() // handled above

                case .plot:
                    proPanel(.plot, store: store)

                case .services:
                    if let vm = services.serviceCallViewModel {
                        ServiceCallView(viewModel: vm)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ContentUnavailableView(
                            "Services Unavailable",
                            systemImage: "gear.badge.arrow.up.forward",
                            description: Text("Connect to a robot to browse and call ROS2 services.")
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            } else {
                disconnectedEmptyState(for: selectedRightTab)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func disconnectedEmptyState(for tab: RightPanelTab) -> some View {
        if services.sessionMode == .replay {
            replayEmptyState(for: tab)
        } else {
            liveEmptyState(for: tab)
        }
    }

    @ViewBuilder
    private func liveEmptyState(for tab: RightPanelTab) -> some View {
        switch tab {
        case .inspector:
            ContentUnavailableView(
                "No Robot Connected",
                systemImage: "network.slash",
                description: Text("Connect to a robot to inspect live topic messages.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .parameters:
            ContentUnavailableView(
                "No Robot Connected",
                systemImage: "slider.horizontal.3",
                description: Text("Connect to a robot to read and edit ROS2 parameters.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .tfTree:
            ContentUnavailableView(
                "No Robot Connected",
                systemImage: "point.3.connected.trianglepath.dotted",
                description: Text("Connect to a robot to view the TF transform tree.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .monitor:
            EmptyView() // handled before this function is called
        case .plot:
            proPanel(.plot, store: nil)
        case .services:
            ContentUnavailableView(
                "No Robot Connected",
                systemImage: "gear.badge.arrow.up.forward",
                description: Text("Connect to a robot to browse and call ROS2 services.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func replayEmptyState(for tab: RightPanelTab) -> some View {
        switch tab {
        case .inspector:
            ContentUnavailableView(
                "No Rosbag Loaded",
                systemImage: "film.stack",
                description: Text("Open an MCAP rosbag file to inspect its topics.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .parameters:
            ContentUnavailableView(
                "Not Available in Replay Mode",
                systemImage: "slider.horizontal.3",
                description: Text("Parameter editing is only available when connected to a live robot.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .tfTree:
            ContentUnavailableView(
                "No Rosbag Loaded",
                systemImage: "point.3.connected.trianglepath.dotted",
                description: Text("Open an MCAP rosbag file containing /tf data.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .monitor:
            EmptyView() // handled before this function is called
        case .plot:
            proPanel(.plot, store: nil)
        case .services:
            EmptyView() // Services tab is live-only; never appears in replay picker
        }
    }

    /// Builds a Pro-injected right-panel tab via `ProUIRegistry`. Shows a graceful
    /// placeholder if the feature isn't installed (free build) — though such tabs
    /// are normally filtered out of the picker entirely.
    @ViewBuilder
    private func proPanel(_ tab: RightPanelTab, store: TopicStore?) -> some View {
        let context = RightPanelContext(
            services: services,
            store: store,
            currentBagTimeSec: ProUIRegistry.shared.currentBagTimeSec
        )
        if let view = ProUIRegistry.shared.makePanel(id: tab.id, context: context) {
            view
        } else {
            ContentUnavailableView(
                "\(tab.displayName) is a Pro feature",
                systemImage: "lock",
                description: Text("Available in the paid edition.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// A compact button that shows the selected topic (or placeholder) and opens the full
    /// topic browser in a popover when clicked.
    @ViewBuilder
    private func topicPickerRow(store: TopicStore) -> some View {
        Button {
            showTopicPicker.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: services.selection.selected.map { TopicIconProvider.icon(for: $0.schemaName) } ?? "list.bullet")
                    .foregroundStyle(.secondary)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 1) {
                    if let topic = services.selection.selected {
                        Text(topic.name)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(topic.schemaName)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else {
                        Text("Select a topic…")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 7))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .help("Click to open the topic picker — choose a topic to inspect in the right panel")
        .accessibilityLabel(services.selection.selected.map { "Selected topic: \($0.name)" } ?? "No topic selected")
        .accessibilityHint("Opens topic browser to select a topic to inspect.")
        .popover(isPresented: $showTopicPicker, arrowEdge: .top) {
            TopicBrowserView(store: store, selection: Binding(
                get: { services.selection.selected },
                set: { topic in
                    // Respect inspector pin: if pinned, don't change selection from topic browser
                    let pinned = UserDefaults.standard.bool(forKey: "inspector.pinned")
                    if !pinned {
                        services.selection.select(topic)
                    }
                    showTopicPicker = false
                }
            ))
            .frame(width: 320, height: 440)
        }
    }

    private var inspectorEmpty: some View {
        VStack(spacing: 12) {
            Image(systemName: "sidebar.right")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text("Select a topic to inspect")
                .foregroundStyle(.secondary)
            Text("Pick a topic from the picker above to start inspecting.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Inspector empty state. Use the topic picker above to select a topic.")
    }

    // MARK: - Placeholders

    @ViewBuilder
    private var notConnectedPlaceholder: some View {
        if services.sessionMode == .replay {
            VStack(spacing: 20) {
                Image(systemName: "film.stack")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("ROS2 Studio — Replay Mode")
                    .font(.title2.bold())
                Text("Open an MCAP rosbag file to start replaying recorded sensor data.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
                Button("Open Rosbag…") {
                    openRosbagPanel()
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Open Rosbag")
                .accessibilityHint("Opens the file picker to choose an MCAP rosbag file.")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 20) {
                Image(systemName: "cube.transparent")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("ROS2 Studio")
                    .font(.title2.bold())
                Text("Connect to a ROS2 robot to start visualizing sensor data.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
                Button("New Connection…") {
                    showingNewConnectionSheet = true
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("New Connection")
                .accessibilityHint("Opens the new connection form.")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        // Left: session mode control
        ToolbarItem(placement: .navigation) {
            SessionModeControl(
                currentMode: services.sessionMode,
                onSwitch: { services.setMode($0) },
                onShowModePicker: nil
            )
        }

        // Center: connection/file status
        ToolbarItem(placement: .principal) {
            if services.sessionMode == .live {
                ConnectionToolbarControl(
                    activeHandles: services.activeConnectionHandles,
                    recentConnections: services.recentConnections.map {
                        RecentConnectionEntry(id: $0.id, name: $0.name, url: $0.url, lastConnectedAt: $0.lastConnectedAt)
                    },
                    profileStore: services.profileStore,
                    connectionManager: services.connectionManager,
                    onShowNewConnection: { showingNewConnectionSheet = true },
                    onConnectResult: { ok, info in
                        if ok {
                            services.toasts.show(.success, title: "Connected", message: info)
                        } else {
                            services.toasts.show(.error, title: "Could not connect", message: info)
                        }
                    }
                )
            } else {
                replayFileIndicator
            }
        }

        // Open Rosbag — replay mode only
        if services.sessionMode == .replay {
            ToolbarItem(placement: .navigation) {
                Button {
                    openRosbagPanel()
                } label: {
                    Label("Open Rosbag", systemImage: "film.stack")
                }
                .help("Open Rosbag (MCAP) file (⌘O)")
                .accessibilityLabel("Open Rosbag")
                .accessibilityHint("Choose an MCAP rosbag file to replay.")
            }
        }

        // Hidden keyboard shortcut to open Publish sheet (cmd+shift+P).
        // The visible Publish button now lives in the 3D panel's top-right toolbar.
        if services.sessionMode == .live {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showPublishSheet = true
                } label: {
                    EmptyView()
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .opacity(0)
                .accessibilityHidden(true)
            }
        }

        // Recording — live mode only, placed on the right side.
        // REC-002: recordingState is read here so the @ToolbarContentBuilder closure
        if services.sessionMode == .live {
            ToolbarItem(placement: .primaryAction) {
                // Recording is a Pro feature: the toolbar content (and its per-connection
                // lifecycle) is supplied by the rosbag/recording plugin. Absent in the
                // free build.
                if let recordingToolbar = ProUIRegistry.shared.makeRecordingToolbar(services: services) {
                    recordingToolbar
                }
            }
        }
    }

    /// Compact indicator showing the loaded rosbag filename (or hint when empty).
    private var replayFileIndicator: some View {
        HStack(spacing: 5) {
            Image(systemName: "doc.fill")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            if let url = services.replayBagURL {
                Text(url.lastPathComponent)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Text("No bag loaded")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 7))
        .fixedSize()
    }

}

// MARK: - Connection Toolbar Control (Xcode scheme-selector style)

/// Compact top-center control showing connection status + active robot name.
/// Clicking reveals a menu to connect/disconnect/switch robots.
private struct ConnectionToolbarControl: View {
    let activeHandles: [ConnectionHandle]
    let recentConnections: [RecentConnectionEntry]
    let profileStore: ProfileStore
    let connectionManager: ConnectionManager
    let onShowNewConnection: () -> Void
    let onConnectResult: @MainActor (Bool, String?) -> Void

    @State private var savedProfiles: [StoredProfile] = []
    @State private var connectingID: UUID? = nil

    private var isConnected: Bool { !activeHandles.isEmpty }

    private var statusIcon: String {
        isConnected ? "circle.fill" : "circle"
    }

    private var statusColor: Color {
        isConnected ? .green : .secondary
    }

    private var labelText: String {
        if let first = activeHandles.first {
            return first.profile.name
        }
        return "No Connection"
    }

    var body: some View {
        Menu {
            menuContent
        } label: {
            HStack(spacing: 5) {
                Image(systemName: statusIcon)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(statusColor)
                Text(labelText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isConnected ? .primary : .secondary)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 7))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel(isConnected ? "Connected to \(labelText)" : "No connection — tap to connect")
        .accessibilityHint("Opens connection management menu.")
        .task { await refreshProfiles() }
    }

    @ViewBuilder
    private var menuContent: some View {
        // Active connections section
        if !activeHandles.isEmpty {
            Section("Active") {
                ForEach(activeHandles) { handle in
                    HStack {
                        Label {
                            VStack(alignment: .leading) {
                                Text(handle.profile.name)
                                Text(handle.profile.url.absoluteString)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "circle.fill")
                                .foregroundStyle(.green)
                        }
                    }
                    Button(role: .destructive) {
                        Task { try? await connectionManager.disconnect(handle) }
                    } label: {
                        Label("Disconnect \(handle.profile.name)", systemImage: "xmark.circle")
                    }
                }
            }
            Divider()
        }

        // Saved profiles
        if !savedProfiles.isEmpty {
            Section("Saved Profiles") {
                ForEach(savedProfiles) { profile in
                    let alreadyActive = activeHandles.contains { $0.profile.url == profile.url && $0.profile.name == profile.name }
                    Button {
                        if !alreadyActive {
                            Task { await connectProfile(name: profile.name, url: profile.url) }
                        }
                    } label: {
                        Label {
                            VStack(alignment: .leading) {
                                Text(profile.name)
                                Text(profile.url.absoluteString)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: alreadyActive ? "circle.fill" : "circle")
                                .foregroundStyle(alreadyActive ? Color.green : Color.secondary)
                        }
                    }
                    .disabled(alreadyActive)
                }
            }
            Divider()
        } else if !recentConnectionsToShow.isEmpty {
            // Recent connections (only when no saved profiles and not already active)
            Section("Recent") {
                ForEach(recentConnectionsToShow) { entry in
                    Button {
                        Task { await connectRecent(entry) }
                    } label: {
                        Label {
                            VStack(alignment: .leading) {
                                Text(entry.name)
                                Text(entry.url.absoluteString)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "clock")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Divider()
        }

        Button {
            onShowNewConnection()
        } label: {
            Label("New Connection…", systemImage: "plus.circle")
        }
    }

    private var recentConnectionsToShow: [RecentConnectionEntry] {
        guard activeHandles.isEmpty else { return [] }
        let savedURLs = Set(savedProfiles.map(\.url))
        return recentConnections.filter { !savedURLs.contains($0.url) }
    }

    private func refreshProfiles() async {
        savedProfiles = await profileStore.list()
    }

    private func connectProfile(name: String, url: URL) async {
        do {
            let profile = ManagerProfile(name: name, url: url)
            _ = try await connectionManager.connect(profile)
            onConnectResult(true, url.absoluteString)
        } catch {
            onConnectResult(false, error.localizedDescription)
        }
    }

    private func connectRecent(_ entry: RecentConnectionEntry) async {
        do {
            let profile = ManagerProfile(name: entry.name, url: entry.url)
            _ = try await connectionManager.connect(profile)
            onConnectResult(true, entry.url.absoluteString)
        } catch {
            onConnectResult(false, error.localizedDescription)
        }
    }
}

// MARK: - New Connection Sheet Host

/// Thin host view that owns the ConnectionViewModel for the new-connection sheet.
/// Using @State with a class reference — the ViewModel is created lazily on first
/// render so it's always on the MainActor (all SwiftUI view body calls are on main).
private struct NewConnectionSheetHost: View {
    let connectionManager: ConnectionManager
    let profileStore: ProfileStore
    let onConnectResult: @MainActor (Bool, String?) -> Void
    let onSave: (@MainActor (String) -> Void)?

    @State private var viewModel: ConnectionViewModel?

    var body: some View {
        Group {
            if let vm = viewModel {
                NewConnectionSheet(
                    viewModel: vm,
                    profileStore: profileStore,
                    onConnect: onConnectResult,
                    onSave: onSave
                )
            }
        }
        .onAppear {
            if viewModel == nil {
                viewModel = ConnectionViewModel(manager: connectionManager)
            }
        }
    }
}

// MARK: - Core Publish Sheet (free build — no templates)

/// Basic publish sheet for the Community build: the template-free publish form.
/// The Pro build replaces this via `ProUIRegistry.makePublishSheet` with a variant
/// that adds the templates sidebar.
private struct CorePublishSheet: View {
    let publishService: PublishService?
    let topics: [TopicDescriptor]
    let isEnabled: Bool
    @ObservedObject var formState: PublishFormState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Publish Message", systemImage: "paperplane")
                    .font(.headline)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
                .accessibilityLabel("Close Publish panel")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            PublishView(
                service: publishService,
                topics: topics,
                isEnabled: isEnabled,
                state: formState
            )
        }
        .frame(minWidth: 560, minHeight: 400)
        .onExitCommand { dismiss() }
    }
}

// MARK: - TF Tree tab (inline, no sheet chrome)

private struct TFTreeTabView: View {
    let tfTree: TFTree?
    let frames: [String]
    var selectedFrame: Binding<String?> = .constant(nil)

    @State private var edges: [TFEdgeInfo] = []
    @State private var rateInfos: [String: TFEdgeRateInfo] = [:]
    @State private var rateHistory: [String: [(Date, Double)]] = [:]
    @State private var previousHz: [String: Double] = [:]

    @AppStorage("tfRateThresholdHz") private var rateThreshold: Double = 1.0
    @AppStorage("tfStaleAfterSeconds") private var staleAfter: Double = 5.0
    @State private var showDiagram: Bool = false

    var body: some View {
        Group {
            if frames.isEmpty {
                ContentUnavailableView(
                    "No TF frames yet",
                    systemImage: "antenna.radiowaves.left.and.right.slash",
                    description: Text("Connect to a robot publishing /tf or /tf_static."))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                if showDiagram {
                    TFTreeDiagramView(
                        edges: edges,
                        rateInfos: rateInfos,
                        rateThreshold: rateThreshold,
                        staleAfter: staleAfter,
                        selectedFrame: selectedFrame.wrappedValue,
                        onFrameSelected: { name in selectedFrame.wrappedValue = name })
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(rootFrames(), id: \.self) { root in
                                FrameNodeView(
                                    name: root, depth: 0, edges: edges,
                                    rateInfos: rateInfos, rateThreshold: rateThreshold,
                                    staleAfter: staleAfter, rateHistory: rateHistory,
                                    selectedFrame: selectedFrame)
                            }
                        }
                        .padding(16)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showDiagram.toggle()
                } label: {
                    Image(systemName: showDiagram ? "list.bullet" : "square.grid.3x3")
                        .help(showDiagram ? "Switch to text tree" : "Switch to visual diagram")
                }
                .buttonStyle(.plain)
            }
        }
        .task {
            while !Task.isCancelled {
                if let tfTree {
                    edges = await tfTree.edgesWithMetadata()
                    let rates = await tfTree.frameRates(windowSeconds: 2.0)
                    var map: [String: TFEdgeRateInfo] = [:]
                    for r in rates { map[r.child] = r }
                    rateInfos = map

                    for r in rates {
                        var history = rateHistory[r.child] ?? []
                        history.append((Date(), r.hz))
                        let cutoff = Date().addingTimeInterval(-30)
                        history.removeAll { $0.0 < cutoff }
                        rateHistory[r.child] = history
                    }
                }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
    }

    private func rootFrames() -> [String] {
        let children = Set(edges.map(\.child))
        let parents = Set(edges.map(\.parent))
        let roots = parents.subtracting(children)
        return roots.isEmpty ? Array(parents).sorted() : Array(roots).sorted()
    }
}


private struct FrameNodeView: View {
    let name: String
    let depth: Int
    let edges: [TFEdgeInfo]
    var rateInfos: [String: TFEdgeRateInfo] = [:]
    var rateThreshold: Double = 1.0
    var staleAfter: Double = 5.0
    var rateHistory: [String: [(Date, Double)]] = [:]
    var selectedFrame: Binding<String?> = .constant(nil)

    @State private var isExpanded = false

    private var edgeInfo: TFEdgeInfo? {
        edges.first { $0.child == name }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: depth == 0 ? "circle.fill" : "circle")
                    .font(.system(size: 8))
                    .foregroundStyle(.tint)
                Text(name)
                    .font(.body.monospaced())
                Spacer(minLength: 4)
                if let info = edgeInfo {
                    if info.isStatic {
                        Text("static")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                    } else {
                        TFBadge(
                            rateInfo: rateInfos[name],
                            threshold: rateThreshold,
                            staleAfter: staleAfter,
                            sparklineSamples: rateHistory[name] ?? [])
                    }
                }
                if edgeInfo != nil {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
            .padding(.leading, CGFloat(depth) * 16)
            .background(
                selectedFrame.wrappedValue == name
                    ? Color.accentColor.opacity(0.12)
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: 4))
            .onTapGesture {
                let current = selectedFrame.wrappedValue
                selectedFrame.wrappedValue = (current == name) ? nil : name
                if edgeInfo != nil { isExpanded.toggle() }
            }
            .contextMenu {
                Button("Copy Frame Name") {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(name, forType: .string)
                }
                if let info = edgeInfo {
                    Button("Copy Transform") {
                        let t = info.translation
                        let r = info.rotation
                        let text = String(format: "%@: x=%.3f y=%.3f z=%.3f r=%.1f° p=%.1f° y=%.1f°",
                                         name, t.x, t.y, t.z, r.roll, r.pitch, r.yaw)
                        let pb = NSPasteboard.general
                        pb.clearContents()
                        pb.setString(text, forType: .string)
                    }
                    Button("Jump to Frame") {
                        NotificationCenter.default.post(
                            name: .jumpToFrame,
                            object: name)
                    }
                }
            }

            if isExpanded, let info = edgeInfo {
                FrameDetailView(info: info)
                    .padding(.leading, CGFloat(depth) * 16 + 20)
            }

            ForEach(edges.filter { $0.parent == name }.sorted(by: { $0.child < $1.child }), id: \.child) { edge in
                FrameNodeView(
                    name: edge.child, depth: depth + 1, edges: edges,
                    rateInfos: rateInfos, rateThreshold: rateThreshold,
                    staleAfter: staleAfter, rateHistory: rateHistory,
                    selectedFrame: selectedFrame)
            }
        }
    }
}

// MARK: - TF Rate Badge

private struct TFBadge: View {
    let rateInfo: TFEdgeRateInfo?
    let threshold: Double
    let staleAfter: Double
    let sparklineSamples: [(Date, Double)]

    private var statusColor: Color {
        guard let info = rateInfo, !info.isStatic else { return .secondary }
        if info.ageSeconds > staleAfter { return .red }
        if info.hz == 0 { return .red }
        if info.hz < threshold { return .orange }
        return Color(red: 0.24, green: 0.83, blue: 0.5)
    }

    private var statusText: String {
        guard let info = rateInfo, !info.isStatic else { return "" }
        if info.ageSeconds > staleAfter { return "stale" }
        if info.hz == 0 { return "0 Hz" }
        return info.hz < 1 ? String(format: "%.1f Hz", info.hz) : String(format: "%.0f Hz", info.hz)
    }

    var body: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(statusColor)
                .frame(width: 5, height: 5)
            Text(statusText)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
            if !sparklineSamples.isEmpty && sparklineSamples.count > 2 {
                RateSparkline(samples: sparklineSamples, color: statusColor)
                    .frame(width: 32, height: 12)
            }
        }
    }
}

// MARK: - Rate Sparkline

private struct RateSparkline: View {
    let samples: [(Date, Double)]
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let maxVal = max(samples.map(\.1).max() ?? 1.0, 0.1)
            Path { path in
                for (i, sample) in samples.enumerated() {
                    let x = geo.size.width * CGFloat(i) / CGFloat(max(samples.count - 1, 1))
                    let y = geo.size.height * (1.0 - CGFloat(sample.1 / maxVal))
                    if i == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            .stroke(color.opacity(0.7), lineWidth: 1)
        }
    }
}

private struct FrameDetailView: View {
    let info: TFEdgeInfo

    private var wallClockAgeSeconds: Double {
        let nowNs = UInt64(Date().timeIntervalSince1970 * 1_000_000_000)
        guard nowNs > info.receivedAtNs else { return 0 }
        return Double(nowNs - info.receivedAtNs) / 1_000_000_000.0
    }

    private var ageText: String {
        if info.isStatic { return "—" }
        let age = wallClockAgeSeconds
        if age < 1.0 { return String(format: "%.2fs", age) }
        if age < 60.0 { return String(format: "%.1fs", age) }
        return String(format: "%.0fs", age)
    }

    private var ageStatus: TFAgeStatus {
        let greenThresh = max(0.1, UserDefaults.standard.double(forKey: "tfStalenessGreen"))
        let yellowThresh = max(0.5, UserDefaults.standard.double(forKey: "tfStalenessYellow"))
        return TFAgeStatus(wallClockAgeSeconds: wallClockAgeSeconds,
                           greenThreshold: greenThresh,
                           yellowThreshold: yellowThresh)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            let t = info.translation
            let r = info.rotation
            detailRow("pos", value: String(format: "x  %.3f  y  %.3f  z  %.3f", t.x, t.y, t.z))
            detailRow("rot", value: String(format: "r  %.1f°  p  %.1f°  y  %.1f°", r.roll, r.pitch, r.yaw))
            if !info.isStatic {
                detailRow("Hz", value: String(format: "%.1f", info.hz))
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("age")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, alignment: .trailing)
                    Circle()
                        .fill(Color(red: ageStatus.color.r, green: ageStatus.color.g, blue: ageStatus.color.b))
                        .frame(width: 5, height: 5)
                    Text(ageText)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.primary)
                }
                if info.latencyNs > 0 && info.latencyNs < 10_000_000_000 {
                    let latencyMs = Double(info.latencyNs) / 1_000_000.0
                    let latencyColor: Color = latencyMs < 50 ? .green : latencyMs < 200 ? .orange : .red
                    detailRow("lat", value: String(format: "%.1f ms", latencyMs))
                        .foregroundStyle(latencyColor)
                }
            }
            detailRow("src", value: info.isStatic ? "[static]" : "/tf")
        }
        .padding(.vertical, 4)
    }

    private func detailRow(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 32, alignment: .trailing)
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.primary)
        }
    }
}
