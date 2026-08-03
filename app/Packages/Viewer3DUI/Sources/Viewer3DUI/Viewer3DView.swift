import SwiftUI
import MetalKit
import MetalCore
import MeshLoader
import PointCloudRenderer
import RobotModelRenderer
import TopicStore
import TFTree
import Transport
import PublishService

/// Full 3D viewport with multi-layer compositing (RViz-style Displays panel).
///
/// Pass `availableTopics` from the live connection; the view auto-seeds layers
/// on first connect and lets the user add/remove/reorder via the Layers panel.
/// Image/CompressedImage layers render as a picture-in-picture overlay.
public enum Viewer3DMode: String, CaseIterable {
    case scene = "Scene"
    case tfUniverse = "TF Universe"
}

public struct Viewer3DView: View {
    private let store: TopicStore
    private let tfTree: TFTree
    private let robotModel: RobotModel?
    private let loadedMeshes: [String: LoadedMesh]
    private let fixedFrame: String
    /// All topics the connected robot exposes — feeds the [+] layer picker.
    private let availableTopics: [TopicDescriptor]
    private let availableFrames: [String]
    private let fixedFrameBinding: Binding<String>?

    /// External binding for the layer list — owned by AppServices for per-profile
    /// persistence. When non-nil, the view reads/writes through this binding instead
    /// of local @State.
    private let layersBinding: Binding<[DisplayLayer]>?

    /// Saved camera blob to restore when the renderer is first set up.
    private let savedCameraData: Data?

    /// Called with encoded camera blob whenever the camera changes.
    /// AppServices uses this to persist state per profile.
    private let onCameraChanged: ((Data) -> Void)?

    /// Optional publish service injected from outside (AppServices).
    /// Used by the Nav Goal tool to publish PoseStamped goals.
    private let publishService: PublishService?
    /// Fixed frame name used in the Nav Goal PoseStamped header.
    /// Mirrors the `fixedFrame` string for publishing.

    /// Called when the user taps "Load Robot Description…" in the Layers panel.
    private let onLoadURDF: (() -> Void)?

    /// Called when the user taps the Publish button in the 3D panel top-right toolbar.
    private let onShowPublish: (() -> Void)?
    private let onLoadStaticMap: (() -> Void)?
    private let onLoadMeshMap: (() -> Void)?
    /// Called when a Pose Estimate is successfully published.
    private let onPoseEstimateSent: (() -> Void)?
    /// Called when the fixed frame is auto-switched to "map" for pose estimation.
    private let onFixedFrameAutoSwitched: ((String) -> Void)?

    /// Binding for the currently selected TF frame name (set by click in 3D, cleared by clicking empty space).
    private let selectedFrameName: Binding<String?>?

    /// When non-nil, use this externally-owned viewModel instead of creating one internally.
    private let externalViewModel: Viewer3DViewModel?
    /// Whether to show the layers sidebar inside this view. Set false when a parent
    /// (e.g. MainWindow) renders its own LayersPanel alongside the 3D viewport.
    private let showLayersSidebar: Bool
    /// When true, the 3D viewport enters TF Universe mode (interactive TF tree visualization).
    /// Bound from MainWindow — set via .tfUniverseRequested / .tfUniverseExit notifications.
    @Binding private var tfUniverseMode: Bool
    private var mode: Viewer3DMode {
        tfUniverseMode ? .tfUniverse : .scene
    }
    private let viewModel: Viewer3DViewModel
    /// LOD threshold forwarded to PointCloudMetalView → PointCloudRenderer.
    private let lodThreshold: Int
    /// Target render FPS forwarded to PointCloudMetalView's MTKView.
    private let renderFPS: Int
    /// Drawable resolution scale forwarded to PointCloudMetalView.
    private let renderResolution: Double
    /// Called on every Metal frame draw. Forwarded to PointCloudMetalView for FPS tracking.
    private let onFrameDrawn: (() -> Void)?
    @State private var activeTool: CameraTool = .orbit
    /// Local layer list — used only when `layersBinding` is nil (e.g. demo/MCAP).
    @State private var localLayers: [DisplayLayer] = []
    /// Polled camera orientation for the ViewCube widget (azimuth, elevation).
    @State private var cameraAzimuth: Float = 0
    @State private var cameraElevation: Float = 0.45

    // MARK: - Pose Estimate tool state

    @AppStorage("poseEstimate.topic")  private var poseEstimateTopic: String  = "/initialpose"
    @AppStorage("poseEstimate.frame")  private var poseEstimateFrame: String  = "map"
    @AppStorage("poseEstimate.covXY")  private var poseEstimateCovXY: Double  = 0.25
    @AppStorage("poseEstimate.covYaw") private var poseEstimateCovYaw: Double = 0.0685
    @State private var lastPoseEstimateHit: (x: Float, z: Float, yaw: Float)?
    @State private var showDragHint = false
    @State private var showPoseEstimateSettings = false

    // MARK: - Active layer list (routes through binding when available)

    private var layers: [DisplayLayer] {
        layersBinding?.wrappedValue ?? localLayers
    }

    /// Write a new layer list through whichever binding is active.
    private func setLayers(_ newLayers: [DisplayLayer]) {
        layersListBinding.wrappedValue = newLayers
    }

    public init(
        store: TopicStore,
        tfTree: TFTree,
        robotModel: RobotModel? = nil,
        loadedMeshes: [String: LoadedMesh] = [:],
        fixedFrame: String = "world",
        availableTopics: [TopicDescriptor] = [],
        availableFrames: [String] = [],
        fixedFrameBinding: Binding<String>? = nil,
        layersBinding: Binding<[DisplayLayer]>? = nil,
        savedCameraData: Data? = nil,
        onCameraChanged: ((Data) -> Void)? = nil,
        publishService: PublishService? = nil,
        onLoadURDF: (() -> Void)? = nil,
        onShowPublish: (() -> Void)? = nil,
        onLoadStaticMap: (() -> Void)? = nil,
        onLoadMeshMap: (() -> Void)? = nil,
        onPoseEstimateSent: (() -> Void)? = nil,
        onFixedFrameAutoSwitched: ((String) -> Void)? = nil,
        selectedFrameName: Binding<String?>? = nil,
        externalViewModel: Viewer3DViewModel? = nil,
        showLayersSidebar: Bool = true,
        tfUniverseMode: Binding<Bool> = .constant(false),
        lodThreshold: Int = 500_000,
        renderFPS: Int = 60,
        renderResolution: Double = 0.75,
        onFrameDrawn: (() -> Void)? = nil
    ) {
        self.store = store
        self.tfTree = tfTree
        self.robotModel = robotModel
        self.loadedMeshes = loadedMeshes
        self.fixedFrame = fixedFrame
        self.availableTopics = availableTopics
        self.availableFrames = availableFrames
        self.fixedFrameBinding = fixedFrameBinding
        self.layersBinding = layersBinding
        self.savedCameraData = savedCameraData
        self.onCameraChanged = onCameraChanged
        self.publishService = publishService
        self.onLoadURDF = onLoadURDF
        self.onShowPublish = onShowPublish
        self.onLoadStaticMap = onLoadStaticMap
        self.onLoadMeshMap = onLoadMeshMap
        self.onPoseEstimateSent = onPoseEstimateSent
        self.onFixedFrameAutoSwitched = onFixedFrameAutoSwitched
        self.selectedFrameName = selectedFrameName
        self.externalViewModel = externalViewModel
        self.showLayersSidebar = showLayersSidebar
        self._tfUniverseMode = tfUniverseMode
        self.lodThreshold = lodThreshold
        self.renderFPS = renderFPS
        self.renderResolution = renderResolution
        self.onFrameDrawn = onFrameDrawn
        self.viewModel = externalViewModel ?? Viewer3DViewModel(store: store, tfTree: tfTree)
    }

    // MARK: - Visible layers (for subscription)

    private var visibleLayers: [DisplayLayer] {
        layers.filter(\.isVisible)
    }

    // MARK: - Image overlay topics (for PiP)

    private var imageTopics: [(topic: String, image: CGImage)] {
        layers
            .filter { ($0.type == .image || $0.type == .compressedImage) && $0.isVisible }
            .compactMap { layer in
                guard let img = viewModel.latestImages[layer.topic] else { return nil }
                return (topic: layer.topic, image: img)
            }
    }

    // MARK: - Body

    @ViewBuilder
    public var body: some View {
        mainContent
            .modifier(Viewer3DSubscriptions(
                viewModel: viewModel,
                layers: layers,
                activeTool: $activeTool,
                fixedFrameBinding: fixedFrameBinding,
                layersListBinding: layersListBinding,
                robotModel: robotModel,
                loadedMeshes: loadedMeshes,
                boxMeshes: boxMeshes,
                setUp: setUpAndSubscribe,
                tfTree: tfTree,
                selectedFrameName: selectedFrameName,
                availableFrames: availableFrames,
                onFixedFrameAutoSwitched: onFixedFrameAutoSwitched))
}

    @ViewBuilder
    private var mainContent: some View {
        VStack(spacing: 0) {
            // Mode switcher tab bar — only when the TF Universe mode is installed (Pro).
            if ViewportModeRegistry.shared.isTFUniverseAvailable {
                HStack {
                    Picker("Mode", selection: $tfUniverseMode) {
                        Text("Scene").tag(false)
                        Text("TF Universe").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 280)
                    .help("Switch between Scene view and TF Universe interactive tree visualization")
                }
                .padding(.horizontal)
                .padding(.vertical, 6)

                Divider()
            }

            // Content area with cross-fade
            ZStack {
                if !tfUniverseMode {
                    if viewModel.isReady, let ctx = viewModel.metalContext {
                        HStack(spacing: 0) {
                            if showLayersSidebar {
                                layersSidebar
                                Divider()
                            }
                            metalCanvas(ctx: ctx)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .transition(.asymmetric(
                            insertion: .opacity,
                            removal: .opacity.combined(with: .scale(scale: 0.96))))
                    } else if viewModel.subscriptionError != nil {
                        ContentUnavailableView(
                            "Metal unavailable",
                            systemImage: "exclamationmark.triangle",
                            description: Text("No GPU found or Metal initialisation failed"))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ProgressView("Initialising 3D renderer…")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                if tfUniverseMode, let ctx = viewModel.metalContext,
                   let universe = ViewportModeRegistry.shared.makeTFUniverse(
                    TFUniverseContext(
                        tfTree: tfTree,
                        metalContext: ctx,
                        fixedFrame: fixedFrame,
                        onExit: {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                tfUniverseMode = false
                            }
                        })) {
                    universe
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 1.04)),
                            removal: .opacity))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .animation(.easeInOut(duration: 0.35), value: tfUniverseMode)

            statusBar
        }
    }

    // MARK: - Layers binding helper

    /// Returns a `Binding<[DisplayLayer]>` that routes through `layersBinding`
    /// when present, or the local `$localLayers` state binding otherwise.
    private var layersListBinding: Binding<[DisplayLayer]> {
        layersBinding ?? $localLayers
    }

    // MARK: - Layers sidebar (pure SwiftUI, docked left of the Metal canvas)

    private var layersSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            LayersPanel(
                layers: layersListBinding,
                availableTopics: availableTopics,
                onLoadURDF: onLoadURDF,
                onLoadStaticMap: onLoadStaticMap,
                onLoadMeshMap: onLoadMeshMap,
                robotModel: robotModel,
                loadedMeshKeys: Set(loadedMeshes.keys),
                onOverrideLinkMesh: { [robotModel] linkName, url in
                    guard let model = robotModel,
                          let link = model.links.first(where: { $0.name == linkName }),
                          let meshKey = link.meshKey,
                          let rmr = viewModel.robotRenderer,
                          let ctx = viewModel.metalContext
                    else { return }
                    do {
                        let loaded = try MeshLoader(context: ctx).load(from: url)
                        rmr.overrideLinkMesh(meshKey: meshKey, with: loaded)
                    } catch {
                        // Path saved in settings; reload on next model set
                    }
                },
                viewModel: viewModel)
                .padding(8)
            Spacer()
        }
        .frame(width: 276)
        .frame(maxHeight: .infinity)
        .background(.background)
    }

    // MARK: - Metal canvas

    @ViewBuilder
    private func metalCanvas(ctx: MetalContext) -> some View {
        let hasPointLayers = !layers.filter(\.isVisible).filter(\.type.isPointBased).isEmpty
        let hasRobotModelLayer = viewModel.robotModelLayerVisible && robotModel != nil
        let hasSomethingToShow = hasPointLayers || hasRobotModelLayer

        if hasSomethingToShow,
           let pcr = viewModel.pointCloudRenderer {
            ZStack(alignment: .bottom) {
                PointCloudMetalView(
                    renderer: pcr,
                    context: ctx,
                    colorMode: .axis(.z),
                    activeTool: activeTool,
                    onNavGoalSelected: { x, y, yaw in
                        Task { await publishNavGoal(x: x, y: y, yaw: yaw) }
                    },
                    onPoseEstimateSelected: { hitX, hitZ, yaw, wasTap in
                        Task {
                            await publishPoseEstimate(hitX: hitX, hitZ: hitZ, yaw: yaw)
                            lastPoseEstimateHit = (x: hitX, z: hitZ, yaw: yaw)
                            if wasTap {
                                showDragHint = true
                                try? await Task.sleep(for: .milliseconds(1500))
                                showDragHint = false
                            }
                            // Fade out after 3s
                            guard let pcr2 = viewModel.pointCloudRenderer else { return }
                            try? await Task.sleep(for: .seconds(3))
                            guard lastPoseEstimateHit != nil else { return }
                            for i in stride(from: 14, through: 0, by: -1) {
                                let alpha = Float(i) / 14.0
                                let (fx, fz, fy) = (hitX, hitZ, yaw)
                                pcr2.update(topic: "__pose_estimate_arrow__",
                                            frame: makePoseEstimateArrowFrame(x: fx, z: fz, yaw: fy, alpha: alpha))
                                pcr2.update(topic: "__pose_estimate_circle__",
                                            frame: makeCovarianceCircleFrame(x: fx, z: fz, radiusMeters: 0.5, alpha: alpha))
                                try? await Task.sleep(for: .milliseconds(33))
                            }
                            pcr2.clearTopic("__pose_estimate_arrow__")
                            pcr2.clearTopic("__pose_estimate_circle__")
                            lastPoseEstimateHit = nil
                        }
                    },
                    onKeyActivatePoseEstimate: {
                        activeTool = activeTool == .poseEstimate ? .orbit : .poseEstimate
                    },
                    onFrameSelected: { name in
                        selectedFrameName?.wrappedValue = name
                    },
                    tfFrameWorldPositions: viewModel.tfFrameWorldPositions,
                    robotRenderer: hasRobotModelLayer ? viewModel.robotRenderer : nil,
                    jointState: viewModel.jointState,
                    lodThreshold: lodThreshold,
                    renderFPS: renderFPS,
                    renderResolution: renderResolution,
                    onFrameDrawn: onFrameDrawn)
                    .frame(minWidth: 200, maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel("3D multi-layer visualization")
                    .accessibilityHint("Drag to rotate or pan. Scroll to zoom.")
                    .overlay {
                        tfFrameLabelsOverlay(pcr: pcr)
                    }
                    .overlay(alignment: .bottomLeading) {
                        viewCubeOverlay(pcr: pcr)
                    }
                    .overlay(alignment: .topTrailing) {
                        topRightToolbar
                    }

                CameraToolbar(
                    activeTool: $activeTool,
                    onZoomIn:  { pcr.zoom(factor: 1.4) },
                    onZoomOut: { pcr.zoom(factor: 1 / 1.4) },
                    onFit:     { pcr.resetCamera() },
                    onTopView: { pcr.topView() },
                    fixedFrameBinding: fixedFrameBinding,
                    availableFrames: availableFrames,
                    onFixedFrameChange: { viewModel.setFixedFrame($0) })
                    .padding(.bottom, 8)

                // Frame readout overlay (bottom-left — shown whenever a frame is selected)
                if let selName = selectedFrameName?.wrappedValue {
                    frameReadoutOverlay(frameName: selName)
                        .padding(.leading, 12)
                        .padding(.bottom, 50)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // Drag hint overlay (shown briefly after a tap with no drag)
                if showDragHint {
                    Text("Drag to set heading")
                        .font(.callout)
                        .padding(8)
                        .background(.regularMaterial, in: Capsule())
                        .transition(.opacity)
                        .zIndex(10)
                }
            }
        } else {
            ContentUnavailableView(
                "No visible layers",
                systemImage: "square.3.layers.3d",
                description: Text("Tap + in the Layers panel to add a topic layer"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - ViewCube overlay

    @ViewBuilder
    private func viewCubeOverlay(pcr: PointCloudRenderer) -> some View {
        ViewCubeWidget(
            azimuth: cameraAzimuth,
            elevation: cameraElevation
        ) { snap in
            pcr.snapView(azimuth: snap.azimuth, elevation: snap.elevation)
            // Update our local state immediately so the widget reflects the snap.
            cameraAzimuth   = snap.azimuth
            cameraElevation = snap.elevation
        }
        .padding(.leading, 8)
        .padding(.bottom, 44) // sit above the toolbar capsule (approx 36pt) + 8pt gap
        .onReceive(Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()) { _ in
            // Poll camera orientation at 10 Hz so the ViewCube stays in sync.
            let (az, el) = pcr.cameraOrientation()
            if az != cameraAzimuth || el != cameraElevation {
                cameraAzimuth   = az
                cameraElevation = el
            }
        }
    }

    // MARK: - TF frame name labels overlay

    /// Projects TF frame world positions to screen and assigns vertical offsets so
    /// co-located labels (within 60pt) stack instead of overlapping.
    private func tfLabelItems(pcr: PointCloudRenderer,
                              viewSize: CGSize) -> [(id: String, pt: CGPoint, vOffset: CGFloat)] {
        let projected: [(id: String, pt: CGPoint)] = viewModel.tfFrameWorldPositions
            .sorted { $0.id < $1.id }
            .compactMap { entry in
                guard let pt = pcr.projectToScreen(entry.metal, viewSize: viewSize) else { return nil }
                return (id: entry.id, pt: pt)
            }

        var offsets: [String: CGFloat] = [:]
        var assigned = Set<String>()
        for i in 0..<projected.count {
            if assigned.contains(projected[i].id) { continue }
            var cluster: [Int] = [i]
            for j in (i+1)..<projected.count {
                let dx = projected[j].pt.x - projected[i].pt.x
                let dy = projected[j].pt.y - projected[i].pt.y
                if sqrt(dx*dx + dy*dy) < 60 { cluster.append(j) }
            }
            for (slot, idx) in cluster.enumerated() {
                offsets[projected[idx].id] = CGFloat(slot) * 16
                assigned.insert(projected[idx].id)
            }
        }
        return projected.map { (id: $0.id, pt: $0.pt, vOffset: offsets[$0.id] ?? 0) }
    }

    /// SwiftUI overlay that renders each TF frame's name at its projected 2D position.
    /// Co-located frames (within 60pt) are stacked vertically with 16pt spacing and a
    /// dashed leader line drawn from each offset label back to the actual frame origin.
    /// Also renders X/Y/Z axis labels at axis tips when enabled.
    @ViewBuilder
    private func tfFrameLabelsOverlay(pcr: PointCloudRenderer) -> some View {
        let tfLayer = layers.first(where: { $0.type == .tfFrames && $0.isVisible })
        let showNames = tfLayer?.settings.showFrameNames ?? false
        let showAxisLabels = tfLayer?.settings.axisShowLabels ?? false
        let axisLabelSize = tfLayer?.settings.axisLabelSize ?? 10.0
        let axisLen = tfLayer?.settings.axisLength ?? 0.3
        let showX = tfLayer?.settings.axisShowX ?? true
        let showY = tfLayer?.settings.axisShowY ?? true
        let showZ = tfLayer?.settings.axisShowZ ?? true

        if (showNames || showAxisLabels) && !viewModel.tfFrameWorldPositions.isEmpty {
            GeometryReader { geo in
                let items = showNames ? tfLabelItems(pcr: pcr, viewSize: geo.size) : []
                ZStack(alignment: .topLeading) {
                    // Leader lines for stacked (offset) labels only
                    if showNames {
                        Canvas { ctx2d, _ in
                            for item in items where item.vOffset > 0 {
                                let labelAnchor = CGPoint(x: item.pt.x, y: item.pt.y - 10 - item.vOffset)
                                var path = Path()
                                path.move(to: labelAnchor)
                                path.addLine(to: item.pt)
                                ctx2d.stroke(path, with: .color(.white.opacity(0.45)),
                                             style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                            }
                        }
                        .allowsHitTesting(false)
                    }

                    // Frame name labels
                    if showNames {
                        ForEach(items, id: \.id) { item in
                            Text(item.id)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.white)
                                .shadow(color: .black, radius: 1, x: 0, y: 0)
                                .position(x: item.pt.x, y: item.pt.y - 10 - item.vOffset)
                                .allowsHitTesting(false)
                        }
                    }

                    // Axis labels (X/Y/Z at tips)
                    if showAxisLabels {
                        ForEach(viewModel.tfFrameWorldPositions, id: \.id) { entry in
                            if let axisData = viewModel.tfFrameAxisData[entry.id] {
                                let len = Float(axisData.length)
                                let showAxes: [(SIMD3<Float>, String, Color, Bool)] = [
                                    (axisData.xAxis * len, "X", .red, showX),
                                    (axisData.yAxis * len, "Y", .green, showY),
                                    (axisData.zAxis * len, "Z", .blue, showZ)
                                ]
                                ForEach(showAxes, id: \.1) { tipOffset, label, color, visible in
                                    if visible {
                                        let tipMetal = axisData.origin + tipOffset
                                        if let tipScreen = pcr.projectToScreen(tipMetal, viewSize: geo.size) {
                                            Text(label)
                                                .font(.system(size: axisLabelSize, weight: .bold, design: .monospaced))
                                                .foregroundStyle(color)
                                                .shadow(color: .black, radius: 0.5, x: 0, y: 0)
                                                .position(x: tipScreen.x + 8, y: tipScreen.y - 4)
                                                .allowsHitTesting(false)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Frame readout overlay (bottom-left)

    @ViewBuilder
    private func frameReadoutOverlay(frameName: String) -> some View {
        FrameReadoutPanel(
            frameName: frameName,
            tfTree: tfTree,
            fixedFrame: fixedFrame)
    }

    // MARK: - Top-right toolbar (Nav Goal + Publish) + Image PiP

    /// Combined top-right overlay: action toolbar buttons above image PiP thumbnails.
    @ViewBuilder
    private var topRightToolbar: some View {
        VStack(alignment: .trailing, spacing: 6) {
            // Action buttons row
            HStack(spacing: 2) {
                // Frame inspector clear button — dismisses the current frame readout
                let hasSelection = selectedFrameName?.wrappedValue != nil
                Button {
                    selectedFrameName?.wrappedValue = nil
                } label: {
                    Image(systemName: "scope")
                        .frame(width: 24, height: 24)
                        .background(
                            hasSelection ? Color.accentColor.opacity(0.18) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .foregroundStyle(hasSelection ? Color.accentColor : Color.primary)
                .help("Frame Inspector — click any TF frame in 3D to see its readout; click here to dismiss")
                .accessibilityLabel("Clear frame selection")

                // Divider
                Rectangle()
                    .fill(Color.secondary.opacity(0.35))
                    .frame(width: 1, height: 16)
                    .padding(.horizontal, 3)

                // Nav Goal toggle button
                let isNavGoalActive = activeTool == .navGoal
                Button {
                    activeTool = isNavGoalActive ? .orbit : .navGoal
                } label: {
                    Image(systemName: "location.north.fill")
                        .frame(width: 24, height: 24)
                        .background(
                            isNavGoalActive ? Color.accentColor.opacity(0.18) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .foregroundStyle(isNavGoalActive ? Color.accentColor : Color.primary)
                .help("Nav Goal — click+drag on the map to set a 2D navigation destination with heading")
                .accessibilityLabel("Nav Goal")

                // Divider
                Rectangle()
                    .fill(Color.secondary.opacity(0.35))
                    .frame(width: 1, height: 16)
                    .padding(.horizontal, 3)

                // Pose Estimate toggle button
                let isPoseEstimateActive = activeTool == .poseEstimate
                Button {
                    activeTool = isPoseEstimateActive ? .orbit : .poseEstimate
                } label: {
                    Image(systemName: "mappin.and.ellipse")
                        .frame(width: 24, height: 24)
                        .background(
                            isPoseEstimateActive ? Color.accentColor.opacity(0.18) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .foregroundStyle(isPoseEstimateActive ? Color.accentColor : Color.primary)
                .disabled(publishService == nil)
                .help(publishService == nil
                      ? "Connect to a robot to publish pose estimates."
                      : "Set 2D Pose Estimate — click to set position, drag to set orientation")
                .accessibilityLabel("Set 2D Pose Estimate")

                // Gear icon — shown only when pose estimate is active
                if isPoseEstimateActive {
                    Button {
                        showPoseEstimateSettings.toggle()
                    } label: {
                        Image(systemName: "gear")
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                    .help("Pose Estimate Settings")
                    .accessibilityLabel("Pose Estimate Settings")
                    .popover(isPresented: $showPoseEstimateSettings, arrowEdge: .bottom) {
                        PoseEstimateSettingsView(
                            topic: $poseEstimateTopic,
                            frame: $poseEstimateFrame,
                            covXY: $poseEstimateCovXY,
                            covYaw: $poseEstimateCovYaw,
                            availableFrames: availableFrames)
                    }
                }

                // Divider
                Rectangle()
                    .fill(Color.secondary.opacity(0.35))
                    .frame(width: 1, height: 16)
                    .padding(.horizontal, 3)

                // Publish button
                Button {
                    onShowPublish?()
                } label: {
                    Image(systemName: "paperplane")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
                .help("Publish a message to a ROS2 topic")
                .accessibilityLabel("Publish")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.regularMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.25), radius: 6, y: 2)

            // Image PiP thumbnails (below toolbar)
            if !imageTopics.isEmpty {
                imagePiP
            }
        }
        .padding(.top, 8)
        .padding(.trailing, 8)
    }

    // MARK: - Image PiP

    private var imagePiP: some View {
        VStack(spacing: 4) {
            ForEach(imageTopics, id: \.topic) { item in
                Image(item.image, scale: 1, label: Text(item.topic))
                    .resizable()
                    .scaledToFit()
                    .frame(width: 200, height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.white.opacity(0.3)))
                    .overlay(alignment: .bottomLeading) {
                        Text(item.topic)
                            .font(.system(size: 8).monospaced())
                            .padding(3)
                            .background(.black.opacity(0.6))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                            .padding(3)
                    }
            }
        }
    }

    // MARK: - Status bar

    @ViewBuilder
    private var statusBar: some View {
        HStack(spacing: 12) {
            if !layers.isEmpty {
                Text("\(viewModel.messageCount) msgs")
            }
            Spacer()
            if let err = viewModel.subscriptionError {
                Label(err, systemImage: "exclamationmark.circle")
                    .foregroundStyle(.red)
            }
        }
        .font(.caption.monospaced())
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.bar)
    }

    // MARK: - Nav Goal publishing

    /// Publish a geometry_msgs/msg/PoseStamped to /goal_pose (Nav2) with the
    /// given world-space position and heading.
    ///
    /// Coordinate mapping: unprojectOntoGroundPlane returns (x, z) on the Y=0
    /// ground plane (Metal Y-up). The callback passes (hitX, hitZ, yaw).
    /// Reverse swizzle: ROS_x = hitZ, ROS_y = -hitX, yaw stays (already ROS).
    @MainActor
    private func publishNavGoal(x: Float, y: Float, yaw: Float) async {
        guard let service = publishService else { return }
        let (rosX, rosY) = reverseSwizzle(metalX: x, metalZ: y)
        let rosYaw = Double(yaw)
        // Quaternion from yaw (rotation around ROS Z axis = up):
        // q = (0, 0, sin(yaw/2), cos(yaw/2))
        let halfYaw = rosYaw / 2.0
        let qz = sin(halfYaw)
        let qw = cos(halfYaw)
        // Nav2 always expects PoseStamped goals in the map frame.
        // The auto-switch in .onChange(of: activeTool) ensures fixedFrame == "map"
        // before any goal can be placed, so Metal world coords are already in map space.
        let payload: [String: Any] = [
            "header": [
                "stamp": ["sec": 0, "nanosec": 0],
                "frame_id": "map"
            ],
            "pose": [
                "position": ["x": rosX, "y": rosY, "z": 0.0],
                "orientation": ["x": 0.0, "y": 0.0, "z": qz, "w": qw]
            ]
        ]
        do {
            let data = try JSONSerialization.data(withJSONObject: payload)
            try await service.publish(.init(
                topic: "/goal_pose",
                messageType: "geometry_msgs/msg/PoseStamped",
                jsonPayload: data))
        } catch {
            // Nav Goal publish failure is non-critical — silently ignored.
            // The green arrow remains visible as a visual indicator.
        }
    }

    // MARK: - Pose Estimate publishing

    @MainActor
    private func publishPoseEstimate(hitX: Float, hitZ: Float, yaw: Float) async {
        guard let service = publishService else { return }
        let (rosX, rosY) = reverseSwizzle(metalX: hitX, metalZ: hitZ)
        let halfYaw = Double(yaw) / 2.0
        let cov = buildCovarianceMatrix(covXY: poseEstimateCovXY, covYaw: poseEstimateCovYaw)
        let payload: [String: Any] = [
            "header": ["stamp": stampNow(), "frame_id": poseEstimateFrame],
            "pose": [
                "pose": [
                    "position": ["x": rosX, "y": rosY, "z": 0.0],
                    "orientation": ["x": 0.0, "y": 0.0, "z": sin(halfYaw), "w": cos(halfYaw)]
                ],
                "covariance": cov
            ]
        ]
        do {
            let data = try JSONSerialization.data(withJSONObject: payload)
            try await service.publish(.init(
                topic: poseEstimateTopic,
                messageType: "geometry_msgs/msg/PoseWithCovarianceStamped",
                jsonPayload: data))
            onPoseEstimateSent?()
        } catch {
            // Pose estimate publish failure is non-critical — silently ignored.
        }
    }

    private func buildCovarianceMatrix(covXY: Double, covYaw: Double) -> [Double] {
        var cov = [Double](repeating: 0, count: 36)
        cov[0]  = covXY    // x variance
        cov[7]  = covXY    // y variance
        cov[14] = 0.001    // z (fixed)
        cov[21] = 0.001    // roll (fixed)
        cov[28] = 0.001    // pitch (fixed)
        cov[35] = covYaw   // yaw variance
        return cov
    }

    private func stampNow() -> [String: Any] {
        let t = Date().timeIntervalSince1970
        return ["sec": Int(t), "nanosec": Int((t - floor(t)) * 1_000_000_000)]
    }

    // MARK: - Setup

    @MainActor
    private func setUpAndSubscribe() async {
        // Push current fixed frame into ViewModel so TF lookups use the right target.
        viewModel.setFixedFrame(fixedFrame)

        do {
            let ctx = try MetalContext()
            let pcr = try PointCloudRenderer(context: ctx)
            let rmr = try RobotModelRenderer(context: ctx)

            // Wire camera change callback for per-profile persistence.
            if let cb = onCameraChanged {
                pcr.onCameraChanged = cb
            }

            // Restore saved camera state (from per-profile config) if available.
            if let data = savedCameraData {
                pcr.applyCamera(data)
            }

            if let model = robotModel {
                if !loadedMeshes.isEmpty {
                    rmr.setModel(model, loadedMeshes: loadedMeshes)
                } else {
                    rmr.setModel(model, meshes: boxMeshes(for: model, device: ctx.device))
                }
            }

            viewModel.setUp(context: ctx, pointCloud: pcr, robot: rmr)
        } catch {
            viewModel.markSetupFailed(error: error)
        }
        await viewModel.startSubscriptions(layers: layers)
    }

    private func boxMeshes(for model: RobotModel, device: MTLDevice) -> [String: MTKMesh] {
        let allocator = MTKMeshBufferAllocator(device: device)
        var meshes: [String: MTKMesh] = [:]
        for link in model.links {
            guard let key = link.meshKey else { continue }
            let mdl = MDLMesh(
                boxWithExtent: SIMD3(0.15, 0.35, 0.15),
                segments: SIMD3(1, 1, 1),
                inwardNormals: false,
                geometryType: .triangles,
                allocator: allocator)
            mdl.vertexDescriptor = RobotModelRenderer.meshVertexDescriptor
            if let mesh = try? MTKMesh(mesh: mdl, device: device) {
                meshes[key] = mesh
            }
        }
        return meshes
    }
}

// MARK: - View modifier (reduces type-checker load on the main body)

private struct Viewer3DSubscriptions: ViewModifier {
    let viewModel: Viewer3DViewModel
    let layers: [DisplayLayer]
    @Binding var activeTool: CameraTool
    let fixedFrameBinding: Binding<String>?
    let layersListBinding: Binding<[DisplayLayer]>
    let robotModel: RobotModel?
    let loadedMeshes: [String: LoadedMesh]
    let boxMeshes: (RobotModel, MTLDevice) -> [String: MTKMesh]
    let setUp: () async -> Void
    let tfTree: TFTree
    let selectedFrameName: Binding<String?>?
    let availableFrames: [String]
    let onFixedFrameAutoSwitched: ((String) -> Void)?

    func body(content: Content) -> some View {
        cameraNotifications(fixedFrameNotifications(robotModifiers(layerModifiers(taskModifiers(content)))))
            .onChange(of: selectedFrameName?.wrappedValue) { _, frameName in
                if let frameName {
                    Task {
                        let chain = await tfTree.chain(from: frameName)
                        viewModel.highlightedChain = chain
                    }
                } else {
                    viewModel.highlightedChain = nil
                }
            }
    }

    private func taskModifiers(_ content: Content) -> some View {
        content
            .task { await setUp() }
            .onDisappear { viewModel.stopSubscriptions() }
    }

    private func layerModifiers(_ content: some View) -> some View {
        content
            .onChange(of: layers) { oldLayers, newLayers in
                for (old, new) in zip(oldLayers, newLayers) where old.isVisible && !new.isVisible {
                    viewModel.pointCloudRenderer?.clearTopic(old.id.uuidString)
                    if old.type == .tfFrames {
                        viewModel.pointCloudRenderer?.clearTopic(old.id.uuidString + "__tips__")
                    }
                }
                let settingsOnly = oldLayers.count == newLayers.count &&
                    zip(oldLayers, newLayers).allSatisfy {
                        $0.id == $1.id && $0.isVisible == $1.isVisible && $0.topic == $1.topic
                    }
                if settingsOnly {
                    viewModel.updateLayerSettings(newLayers)
                } else {
                    Task { await viewModel.startSubscriptions(layers: newLayers) }
                }
            }
            .onChange(of: activeTool) { _, newTool in
                // Clear nav goal arrow when leaving navGoal tool
                if newTool != .navGoal {
                    viewModel.pointCloudRenderer?.clearTopic("__nav_goal_arrow__")
                } else {
                    // Auto-switch to "map" frame when activating navGoal
                    if let binding = fixedFrameBinding, binding.wrappedValue != "map" {
                        binding.wrappedValue = "map"
                    }
                    viewModel.setFixedFrame("map")
                }
                // Clear pose estimate visuals when leaving poseEstimate tool
                if newTool != .poseEstimate {
                    viewModel.pointCloudRenderer?.clearTopic("__pose_estimate_arrow__")
                    viewModel.pointCloudRenderer?.clearTopic("__pose_estimate_circle__")
                } else {
                    // Auto-switch to "map" frame when activating poseEstimate (if available)
                    if availableFrames.contains("map") {
                        if let binding = fixedFrameBinding, binding.wrappedValue != "map" {
                            binding.wrappedValue = "map"
                            viewModel.setFixedFrame("map")
                            onFixedFrameAutoSwitched?("map")
                        }
                    }
                }
            }
    }

    private func robotModifiers(_ content: some View) -> some View {
        content
            .onChange(of: robotModel) { _, model in
                guard let model, let rmr = viewModel.robotRenderer,
                      let device = viewModel.metalContext?.device
                else { return }
                viewModel.robotModel = model
                if !loadedMeshes.isEmpty {
                    rmr.setModel(model, loadedMeshes: loadedMeshes)
                } else {
                    rmr.setModel(model, meshes: boxMeshes(model, device))
                }
            }
            .onChange(of: loadedMeshes) { _, meshes in
                guard !meshes.isEmpty, let model = robotModel,
                      let rmr = viewModel.robotRenderer
                else { return }
                rmr.setModel(model, loadedMeshes: meshes)
            }
    }

    private func fixedFrameNotifications(_ content: some View) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(
                for: Notification.Name("com.jatupon.ros2studio.fixedFrameChanged")
            )) { notif in
                guard let frame = notif.object as? String else { return }
                viewModel.setFixedFrame(frame)
            }
    }

    private func cameraNotifications(_ content: some View) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(
                for: Notification.Name("com.jatupon.ros2studio.resetCamera")
            )) { _ in viewModel.resetCamera() }
            .onReceive(NotificationCenter.default.publisher(for: .jumpToFrame)) { notif in
                guard let frameName = notif.object as? String,
                      let pcr = viewModel.pointCloudRenderer else { return }
                // Find the frame's Metal-space position from the cached positions
                guard let entry = viewModel.tfFrameWorldPositions.first(where: { $0.id == frameName }) else { return }
                let target = entry.metal
                pcr.animateToFrame(target: target)
                // Also select the frame for the inspector readout
                selectedFrameName?.wrappedValue = frameName
            }
    }
}
