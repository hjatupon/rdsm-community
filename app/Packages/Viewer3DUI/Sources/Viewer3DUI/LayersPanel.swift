import SwiftUI
import Transport
import TFTree
import RobotModelCore
import RobotModelRenderer
import MeshLoader
import UniformTypeIdentifiers

// MARK: - LayersPanel
// swiftlint:disable file_length

/// RViz-style "Displays" panel docked to the 3D viewer.
///
/// Shows all active layers with:
/// - Checkbox to show/hide each layer (hidden → unsubscribed, saving bandwidth)
/// - [+] button in the header → topic picker filtered to compatible types
/// - ✕ button per row to remove the layer
/// - ⚙ button per row → per-layer settings popover (colour, opacity, point size, decay)
/// - Drag-to-reorder rows (layers render bottom-to-top like Photoshop)
public struct LayersPanel: View {
    @Binding public var layers: [DisplayLayer]
    /// Full topic list from the connected robot — used to populate the [+] picker.
    let availableTopics: [TopicDescriptor]
    /// When set, shows a "Load Robot Description…" option in the [+] picker.
    var onLoadURDF: (() -> Void)?
    /// When set, shows a "Load Static Map…" option in the [+] picker.
    var onLoadStaticMap: (() -> Void)?
    /// When set, shows a "Load Mesh Map…" option in the [+] picker.
    var onLoadMeshMap: (() -> Void)?
    /// Currently loaded robot model — used to populate the per-link settings UI.
    var robotModel: RobotModel? = nil
    /// Keys present in the loaded mesh dict — drives per-link status dots.
    var loadedMeshKeys: Set<String> = []
    /// Called when the user chooses a replacement mesh file for a specific link.
    var onOverrideLinkMesh: ((String, URL) -> Void)? = nil
    /// ViewModel reference for live Hz / status display.
    var viewModel: Viewer3DViewModel? = nil

    @State private var collapsed = false
    @State private var showingPicker = false
    @State private var settingsID: UUID? = nil
    /// Layer for which the change-topic sheet is open (NF-1).
    @State private var changeTopicLayerID: UUID? = nil

    private let softCap = 8

    private var visibleCount: Int { layers.filter(\.isVisible).count }

    public init(
        layers: Binding<[DisplayLayer]>,
        availableTopics: [TopicDescriptor],
        onLoadURDF: (() -> Void)? = nil,
        onLoadStaticMap: (() -> Void)? = nil,
        onLoadMeshMap: (() -> Void)? = nil,
        robotModel: RobotModel? = nil,
        loadedMeshKeys: Set<String> = [],
        onOverrideLinkMesh: ((String, URL) -> Void)? = nil,
        viewModel: Viewer3DViewModel? = nil
    ) {
        _layers = layers
        self.availableTopics = availableTopics
        self.onLoadURDF = onLoadURDF
        self.onLoadStaticMap = onLoadStaticMap
        self.onLoadMeshMap = onLoadMeshMap
        self.robotModel = robotModel
        self.loadedMeshKeys = loadedMeshKeys
        self.onOverrideLinkMesh = onOverrideLinkMesh
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if !collapsed {
                Divider()
                layerList
                if visibleCount > softCap {
                    Label("\(visibleCount) layers active — performance may degrade",
                          systemImage: "exclamationmark.triangle")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 6)
                }
            }
        }
        .frame(width: 260)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.2), radius: 5, y: 2)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { collapsed.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                        .font(.caption2)
                    Image(systemName: "square.3.layers.3d")
                    Text("3D Layers")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(visibleCount)/\(layers.count)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Collapse or expand the 3D layers panel")
            .accessibilityLabel("3D Layers panel, \(collapsed ? "collapsed" : "expanded")")

            Button {
                showingPicker = true
            } label: {
                Image(systemName: "plus")
                    .font(.caption.weight(.semibold))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Add a new 3D layer from available topics")
            .accessibilityLabel("Add layer")
            .popover(isPresented: $showingPicker, arrowEdge: .trailing) {
                LayerPickerPopover(
                    availableTopics: availableTopics,
                    existingLayers: layers,
                    onAdd: { newLayer in
                        layers.append(newLayer)
                        showingPicker = false
                    },
                    onLoadURDF: {
                        showingPicker = false
                        onLoadURDF?()
                    },
                    onLoadStaticMap: {
                        showingPicker = false
                        onLoadStaticMap?()
                    },
                    onLoadMeshMap: {
                        showingPicker = false
                        onLoadMeshMap?()
                    }
                )
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    // MARK: - Layer list

    @ViewBuilder
    private var layerList: some View {
        if layers.isEmpty {
            Text("No layers — click + to add one")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(8)
        } else {
            List {
                ForEach($layers) { $layer in
                    layerRow($layer)
                        .listRowInsets(EdgeInsets(top: 2, leading: 6, bottom: 2, trailing: 6))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                .onMove { from, to in
                    layers.move(fromOffsets: from, toOffset: to)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .frame(height: min(CGFloat(layers.count) * 36 + 4, 280))
        }
    }

    // MARK: - Layer row

    private func layerRow(_ layer: Binding<DisplayLayer>) -> some View {
        let l = layer.wrappedValue
        return HStack(spacing: 0) {
            // Drag handle
            Image(systemName: "line.3.horizontal")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(width: 20)

            // Visibility checkbox
            Button {
                layer.isVisible.wrappedValue.toggle()
            } label: {
                Image(systemName: l.isVisible ? "checkmark.square.fill" : "square")
                    .foregroundStyle(l.isVisible ? Color.accentColor : Color.secondary)
                    .frame(width: 22)
            }
            .buttonStyle(.plain)
            .help("Toggle layer visibility — hidden layers stop subscribing to save bandwidth")
            .accessibilityLabel("\(l.displayLabel), \(l.isVisible ? "visible" : "hidden")")
            .accessibilityHint("Toggle layer visibility")

            // Type icon
            Image(systemName: l.type.systemImage)
                .font(.caption2)
                .foregroundStyle(l.settings.swiftUIColor)
                .frame(width: 18)

            // Label
            VStack(alignment: .leading, spacing: 1) {
                Text(l.displayLabel)
                    .font(.caption.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(l.type.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 4)

            // Hz / status badge — file-based layers show "File" tag; live layers show Hz/stale
            if l.isVisible && !l.type.isFileBased && l.type != .robotModel, let vm = viewModel {
                layerStatusBadge(for: l, viewModel: vm)
            } else if l.isVisible && l.type.isFileBased {
                Text("File")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .frame(width: 46, alignment: .trailing)
            }

            // Settings ⚙
            Button {
                settingsID = (settingsID == l.id) ? nil : l.id
            } label: {
                Image(systemName: "gearshape")
                    .font(.caption2)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Open layer settings — adjust color, opacity, point size, and more")
            .accessibilityLabel("Layer settings")
            .popover(isPresented: Binding(
                get: { settingsID == l.id },
                set: { if !$0 { settingsID = nil } }
            ), arrowEdge: .trailing) {
                LayerSettingsPopover(layer: layer, knownFrames: viewModel?.knownTFFrames ?? [], onLoadURDF: onLoadURDF, robotModel: robotModel, loadedMeshKeys: loadedMeshKeys, onOverrideLinkMesh: onOverrideLinkMesh)
            }

            // Remove ✕
            Button {
                layers.removeAll { $0.id == l.id }
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Remove this layer from the 3D viewer")
            .accessibilityLabel("Remove layer")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        // NF-3: Right-click context menu
        .contextMenu {
            // Change Topic (NF-1) — only for topic-based layers
            if !l.type.isBuiltIn {
                Button("Change Topic") {
                    changeTopicLayerID = l.id
                }
            }

            // Duplicate
            Button("Duplicate Layer") {
                var copy = l
                copy = DisplayLayer(topic: l.topic, type: l.type, isVisible: l.isVisible)
                if let idx = layers.firstIndex(where: { $0.id == l.id }) {
                    layers.insert(copy, at: layers.index(after: idx))
                }
            }

            // Reset settings
            Button("Reset to Defaults") {
                layer.wrappedValue.settings = LayerSettings()
            }

            Divider()

            // Reorder shortcuts
            Button("Move to Top") {
                if let idx = layers.firstIndex(where: { $0.id == l.id }), idx > 0 {
                    layers.move(fromOffsets: IndexSet(integer: idx), toOffset: 0)
                }
            }
            Button("Move to Bottom") {
                if let idx = layers.firstIndex(where: { $0.id == l.id }), idx < layers.count - 1 {
                    layers.move(fromOffsets: IndexSet(integer: idx), toOffset: layers.count)
                }
            }

            Divider()

            // Remove (destructive)
            Button("Remove Layer", role: .destructive) {
                layers.removeAll { $0.id == l.id }
            }
        }
        // NF-1: Change topic sheet
        .sheet(isPresented: Binding(
            get: { changeTopicLayerID == l.id },
            set: { if !$0 { changeTopicLayerID = nil } }
        )) {
            ChangeTopicSheet(
                currentLayer: l,
                availableTopics: availableTopics
            ) { newTopic in
                layer.wrappedValue.topic = newTopic
                changeTopicLayerID = nil
                // Restart subscriptions through the ViewModel if available
                if let vm = viewModel {
                    vm.changeLayerTopic(layerID: l.id, updatedLayers: layers)
                }
            } onCancel: {
                changeTopicLayerID = nil
            }
        }
    }

    @ViewBuilder
    private func layerStatusBadge(for layer: DisplayLayer, viewModel: Viewer3DViewModel) -> some View {
        let status = viewModel.layerStatus(for: layer.id)
        switch status {
        case .starting:
            EmptyView()
        case .live(let hz):
            HStack(spacing: 3) {
                Circle()
                    .fill(Color(red: 0.24, green: 0.83, blue: 0.5))
                    .frame(width: 5, height: 5)
                Text(hz < 1 ? String(format: "%.1f Hz", hz) : String(format: "%.0f Hz", hz))
                    .font(.system(size: 9).monospaced())
                    .foregroundStyle(.secondary)
            }
            .frame(width: 46, alignment: .trailing)
        case .waiting:
            HStack(spacing: 3) {
                Circle()
                    .fill(Color(red: 0.96, green: 0.72, blue: 0.25))
                    .frame(width: 5, height: 5)
                Text("Wait…")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 46, alignment: .trailing)
        case .stale(let age):
            HStack(spacing: 3) {
                Circle()
                    .fill(Color(red: 0.96, green: 0.72, blue: 0.25))
                    .frame(width: 5, height: 5)
                Text("\(Int(age))s ago")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 46, alignment: .trailing)
        case .noData:
            HStack(spacing: 3) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 7))
                    .foregroundStyle(Color(red: 0.95, green: 0.43, blue: 0.43))
                Text("No data")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 46, alignment: .trailing)
        }
    }
}

// MARK: - Layer Picker Popover

/// Topic browser shown when [+] is tapped. Filters to compatible types only.
private struct LayerPickerPopover: View {
    let availableTopics: [TopicDescriptor]
    let existingLayers: [DisplayLayer]
    let onAdd: (DisplayLayer) -> Void
    let onLoadURDF: (() -> Void)?
    let onLoadStaticMap: (() -> Void)?
    let onLoadMeshMap: (() -> Void)?

    @State private var searchText = ""

    /// All topics that have a known LayerType, de-duped against already-added layers.
    private var candidates: [(TopicDescriptor, LayerType)] {
        let existingTopics = Set(existingLayers.map(\.topic))
        return availableTopics.compactMap { td -> (TopicDescriptor, LayerType)? in
            guard let type = LayerType.detect(from: td.schemaName) else { return nil }
            guard !existingTopics.contains(td.name) else { return nil }
            return (td, type)
        }
        .filter {
            searchText.isEmpty
            || $0.0.name.localizedCaseInsensitiveContains(searchText)
            || $0.1.displayName.localizedCaseInsensitiveContains(searchText)
        }
        .sorted { $0.0.name < $1.0.name }
    }

    /// Built-in layers not already added.
    private var builtInCandidates: [LayerType] {
        let existingBuiltIns = Set(existingLayers.filter { $0.topic.isEmpty }.map(\.type))
        return [LayerType.tfFrames].filter { !existingBuiltIns.contains($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Add Layer")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 6)

            Divider()

            // Built-in layers — always visible, never filtered by search
            if !builtInCandidates.isEmpty {
                Text("BUILT-IN")
                    .font(.system(size: 10, weight: .medium))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 2)

                ForEach(builtInCandidates, id: \.self) { type in
                    pickerRow(label: type.displayName,
                              typeLabel: "Built-in",
                              icon: type.systemImage,
                              color: .secondary) {
                        onAdd(DisplayLayer(topic: "", type: type))
                    }
                }

                Divider()
                    .padding(.top, 4)
            }

            // File-based layers
            Text("FILE-BASED")
                .font(.system(size: 10, weight: .medium))
                .tracking(0.6)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 2)

            if onLoadURDF != nil {
                pickerRow(label: "Load Robot Model…",
                          typeLabel: ".urdf file",
                          icon: "figure.stand",
                          color: .accentColor) {
                    onLoadURDF?()
                }
            }

            pickerRow(label: "Load Mesh Map…",
                      typeLabel: ".ply / .obj",
                      icon: "square.and.arrow.up",
                      color: .accentColor) {
                onLoadMeshMap?()
            }

            Divider()
                .padding(.top, 4)

            if availableTopics.isEmpty {
                Text("No robot connected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(12)
            } else {
                // Topic search
                Text("TOPICS")
                    .font(.system(size: 10, weight: .medium))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 2)

                TextField("Search topics…", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)

                if candidates.isEmpty {
                    Text("All compatible topics already added")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(candidates, id: \.0.name) { td, type in
                                // L-05: show full path (monospaced) + ROS message type
                                pickerRow(
                                    label: td.name,
                                    typeLabel: td.schemaName,
                                    icon: type.systemImage,
                                    color: Color.accentColor
                                ) {
                                    onAdd(DisplayLayer(topic: td.name, type: type))
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 240)
                }
            }
        }
        .frame(width: 280)
        .padding(.bottom, 8)
    }

    private func pickerRow(label: String, typeLabel: String, icon: String,
                           color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(color)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    // L-05: show full path, no truncation
                    Text(label)
                        .font(.caption.monospaced())
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    // L-05: show full ROS message type string (e.g. sensor_msgs/msg/LaserScan)
                    Text(typeLabel)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Image(systemName: "plus.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Layer Settings Popover

private struct LayerSettingsPopover: View {
    @Binding var layer: DisplayLayer
    var knownFrames: [String] = []
    var onLoadURDF: (() -> Void)?
    /// Robot model for per-link settings (visibility, mesh override).
    var robotModel: RobotModel? = nil
    /// Mesh keys that are actually loaded — drives per-link status indicators.
    var loadedMeshKeys: Set<String> = []
    /// Called with (linkName, fileURL) when user picks a replacement mesh for a link.
    var onOverrideLinkMesh: ((String, URL) -> Void)? = nil

    @State private var frameSearch = ""
    /// The link name for which a mesh file picker is currently open.
    @State private var linkForMeshPick: String? = nil

    private var visibleFrameCount: Int {
        knownFrames.filter { !layer.settings.hiddenFrames.contains($0) }.count
    }

    var body: some View {
        // L-03: dispatch to type-specific settings body
        switch layer.type {
        case .tfFrames:
            tfSettingsBody
        case .occupancyGrid:
            occupancyGridSettingsBody
        case .octomap:
            octomapSettingsBody
        case .meshMap:
            meshMapSettingsBody
        case .robotModel:
            robotModelSettingsBody
        case .laserScan:
            laserScanSettingsBody
        case .pointCloud2:
            pointCloud2SettingsBody
        case .odometry:
            odometrySettingsBody
        case .poseStamped:
            poseStampedSettingsBody
        case .markerArray:
            markerArraySettingsBody
        case .path:
            pathSettingsBody
        default:
            genericSettingsBody
        }
    }

    // MARK: TF-specific settings

    private var tfSettingsBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("TF Frames Settings")
                    .font(.subheadline.weight(.semibold))

                Divider()

                // Axis Scale
                LabeledContent("Axis Scale") {
                    Slider(value: $layer.settings.axisLength, in: 0.05...2.0, step: 0.05)
                        .frame(width: 120)
                        .help("Length of each RGB axis arrow at every frame origin (meters)")
                    Text(String(format: "%.2f m", layer.settings.axisLength))
                        .font(.caption.monospaced())
                        .frame(width: 48, alignment: .trailing)
                }

                // Axis Line Width
                LabeledContent("Axis Width") {
                    Slider(value: $layer.settings.axisLineWidth, in: 0.5...4.0, step: 0.25)
                        .frame(width: 120)
                        .help("Line thickness multiplier for axis arrows")
                    Text(String(format: "%.1f×", layer.settings.axisLineWidth))
                        .font(.caption.monospaced())
                        .frame(width: 36, alignment: .trailing)
                }

                // Opacity
                LabeledContent("Opacity") {
                    Slider(value: $layer.settings.opacity, in: 0...1, step: 0.05)
                        .frame(width: 120)
                        .help("Transparency of all TF frame elements — lower to see layers behind")
                    Text("\(Int(layer.settings.opacity * 100))%")
                        .font(.caption.monospaced())
                        .frame(width: 32, alignment: .trailing)
                }

                // Per-axis visibility
                Divider()
                Text("Axis Visibility")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Toggle("X", isOn: $layer.settings.axisShowX)
                        .font(.caption.monospaced())
                        .toggleStyle(.checkbox)
                        .help("Show or hide the red X axis arrow")
                    Toggle("Y", isOn: $layer.settings.axisShowY)
                        .font(.caption.monospaced())
                        .toggleStyle(.checkbox)
                        .help("Show or hide the green Y axis arrow")
                    Toggle("Z", isOn: $layer.settings.axisShowZ)
                        .font(.caption.monospaced())
                        .toggleStyle(.checkbox)
                        .help("Show or hide the blue Z axis arrow")
                }

                // Axis Labels
                Toggle("Axis Labels", isOn: $layer.settings.axisShowLabels)
                    .font(.caption)
                    .help("Show X/Y/Z text labels at the tip of each axis arrow")
                if layer.settings.axisShowLabels {
                    LabeledContent("Label Size") {
                        Slider(value: $layer.settings.axisLabelSize, in: 8...24, step: 1)
                            .frame(width: 100)
                            .help("Font size of axis X/Y/Z labels in points")
                        Text("\(Int(layer.settings.axisLabelSize))pt")
                            .font(.caption.monospaced())
                            .frame(width: 32, alignment: .trailing)
                    }
                }

                // Show Names toggle
                Toggle("Show Names", isOn: $layer.settings.showFrameNames)
                    .font(.caption)
                    .help("Display frame name labels at each TF node in the 3D view")

                // Frame Node
                Divider()
                Text("Frame Node")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                LabeledContent("Node Size") {
                    Slider(value: $layer.settings.frameNodeSize, in: 2...16, step: 1)
                        .frame(width: 100)
                        .help("Size of the marker dot at each frame origin (points)")
                    Text("\(Int(layer.settings.frameNodeSize))pt")
                        .font(.caption.monospaced())
                        .frame(width: 36, alignment: .trailing)
                }
                LabeledContent("Node Shape") {
                    Picker("", selection: $layer.settings.frameNodeShape) {
                        Text("Dot").tag(0)
                        Text("Diamond").tag(1)
                        Text("Cross").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 150)
                    .help("Visual shape at each TF frame origin — Dot for minimal, Diamond for emphasis, Cross for alignment")
                }
                LabeledContent("Color Mode") {
                    Picker("", selection: $layer.settings.frameColorMode) {
                        Text("RGB Axes").tag(0)
                        Text("By Depth").tag(1)
                        Text("Static/Dynamic").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                    .help("How frame nodes are colored: RGB Axes = axis arrows at each node, By Depth = color by Z distance, Static/Dynamic = blue for static, orange for dynamic")
                }

                // Connection Lines
                Divider()
                Text("Connection Lines")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Toggle("Show Links", isOn: $layer.settings.showFrameLinks)
                    .font(.caption)
                    .help("Draw parent-child connection lines between frames in the TF tree")
                if layer.settings.showFrameLinks {
                    LabeledContent("Line Width") {
                        Slider(value: $layer.settings.linkLineWidth, in: 0.5...4.0, step: 0.25)
                            .frame(width: 100)
                            .help("Thickness of the parent-child connection lines")
                        Text(String(format: "%.1f×", layer.settings.linkLineWidth))
                            .font(.caption.monospaced())
                            .frame(width: 36, alignment: .trailing)
                    }
                    LabeledContent("Line Style") {
                        Picker("", selection: $layer.settings.linkLineStyle) {
                            Text("Solid").tag(0)
                            Text("Dashed").tag(1)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 120)
                        .help("Solid for high-confidence links, dashed for estimated or rarely-published links")
                    }
                    HStack {
                        Text("Line Color")
                            .font(.caption)
                            .frame(width: 72, alignment: .trailing)
                        ColorPicker("", selection: Binding(
                            get: { Color(red: layer.settings.linkLineR,
                                          green: layer.settings.linkLineG,
                                          blue: layer.settings.linkLineB) },
                            set: { c in
                                let ns = NSColor(c)
                                layer.settings.linkLineR = Double(ns.redComponent)
                                layer.settings.linkLineG = Double(ns.greenComponent)
                                layer.settings.linkLineB = Double(ns.blueComponent)
                            }))
                        .labelsHidden()
                    }
                }

                // Staleness thresholds (CFG-16)
                Divider()
                Text("Staleness Thresholds")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                LabeledContent("Fresh (s)") {
                    Slider(value: $layer.settings.tfFreshThresholdSec, in: 0.1...5.0, step: 0.1)
                        .frame(width: 100)
                        .help("TF data younger than this is 'fresh' — frames stay fully opaque")
                    Text(String(format: "%.1f", layer.settings.tfFreshThresholdSec))
                        .font(.caption.monospaced())
                        .frame(width: 36, alignment: .trailing)
                }
                LabeledContent("Stale (s)") {
                    Slider(value: $layer.settings.tfStaleThresholdSec, in: 1.0...30.0, step: 0.5)
                        .frame(width: 100)
                        .help("TF data older than this is 'stale' — frames dim to 30% opacity and trigger a toast")
                    Text(String(format: "%.1f", layer.settings.tfStaleThresholdSec))
                        .font(.caption.monospaced())
                        .frame(width: 36, alignment: .trailing)
                }

                // Frame Filter
                if !knownFrames.isEmpty {
                    Divider()

                    HStack {
                        Text("Frame Filter")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(visibleFrameCount)/\(knownFrames.count)")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }

                    // Bulk action buttons
                    HStack(spacing: 6) {
                        Button("Show All") {
                            layer.settings.hiddenFrames = []
                        }
                        .font(.caption2)
                        .help("Show all TF frames")
                        .keyboardShortcut("a", modifiers: [.command, .option])

                        Button("Hide All") {
                            layer.settings.hiddenFrames = Set(knownFrames)
                        }
                        .font(.caption2)
                        .help("Hide all TF frames")
                        .keyboardShortcut("h", modifiers: [.command, .option])

                        Button("Invert") {
                            layer.settings.hiddenFrames = Set(knownFrames).symmetricDifference(layer.settings.hiddenFrames)
                        }
                        .font(.caption2)
                        .help("Invert frame visibility")
                        .keyboardShortcut("i", modifiers: [.command, .option])

                        Spacer()
                    }
                    .padding(.top, 2)

                    TextField("Search…", text: $frameSearch)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                        .help("Filter frame list by name — type part of a frame name to narrow down")

                    let filtered = knownFrames.filter {
                        frameSearch.isEmpty || $0.localizedCaseInsensitiveContains(frameSearch)
                    }.sorted()

                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(filtered, id: \.self) { name in
                            let hidden = layer.settings.hiddenFrames.contains(name)
                            Button {
                                if hidden {
                                    layer.settings.hiddenFrames.remove(name)
                                } else {
                                    layer.settings.hiddenFrames.insert(name)
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: hidden ? "square" : "checkmark.square.fill")
                                        .foregroundStyle(hidden ? Color.secondary : Color.accentColor)
                                        .font(.caption)
                                    Text(name)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(hidden ? Color.secondary : Color.primary)
                                    Spacer()
                                    if hidden {
                                        Text("hidden")
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Divider()
                                Button("Show Only This") {
                                    layer.settings.hiddenFrames = Set(knownFrames).subtracting([name])
                                }
                                if hidden {
                                    Button("Show This") {
                                        layer.settings.hiddenFrames.remove(name)
                                    }
                                } else {
                                    Button("Hide This") {
                                        layer.settings.hiddenFrames.insert(name)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(14)
        }
        .frame(width: 280)
    }

    // MARK: OccupancyGrid settings

    private var occupancyGridSettingsBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Map Settings")
                .font(.subheadline.weight(.semibold))
            Divider()
            colorPickerRow(label: "Occupied Tint")
                .help("Tint applied to occupied (black) cells in the occupancy grid")
            opacityRow
            Divider()
            HStack {
                Text("Free Color")
                    .font(.caption)
                    .frame(width: 80, alignment: .trailing)
                ColorPicker("", selection: Binding(
                    get: { Color(red: layer.settings.freeR,
                                 green: layer.settings.freeG,
                                 blue: layer.settings.freeB) },
                    set: { c in
                        let ns = NSColor(c)
                        layer.settings.freeR = Double(ns.redComponent)
                        layer.settings.freeG = Double(ns.greenComponent)
                        layer.settings.freeB = Double(ns.blueComponent)
                    }))
                .labelsHidden()
                .help("Color of free (value=0) cells — cells where the robot can navigate")
            }
            HStack {
                Text("Unknown Color")
                    .font(.caption)
                    .frame(width: 80, alignment: .trailing)
                ColorPicker("", selection: Binding(
                    get: { Color(red: layer.settings.unknownR,
                                 green: layer.settings.unknownG,
                                 blue: layer.settings.unknownB) },
                    set: { c in
                        let ns = NSColor(c)
                        layer.settings.unknownR = Double(ns.redComponent)
                        layer.settings.unknownG = Double(ns.greenComponent)
                        layer.settings.unknownB = Double(ns.blueComponent)
                    }))
                .labelsHidden()
                .help("Color of unknown (value=-1) cells — areas the sensor hasn't explored")
            }
            Toggle("Show Unknown Cells", isOn: $layer.settings.showUnknownCells)
                .font(.caption)
                .help("Render unknown cells as colored quads — uncheck to show only occupied/free")
            Toggle("Grid Lines", isOn: $layer.settings.showGridLines)
                .font(.caption)
                .help("Draw a grid overlay on the map showing cell boundaries")
        }
        .padding(14)
        .frame(width: 280)
    }

    // MARK: Octomap settings

    private var octomapSettingsBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Octomap Settings")
                .font(.subheadline.weight(.semibold))
            Divider()

            // Voxel visibility
            Toggle("Show Occupied", isOn: $layer.settings.octomapShowOccupied)
                .font(.caption)
                .help("Render occupied voxels (most common — usually what you want)")
            Toggle("Show Free", isOn: $layer.settings.octomapShowFree)
                .font(.caption)
                .help("Render free voxels (areas confirmed empty by sensor)")
            Toggle("Show Unknown", isOn: $layer.settings.octomapShowUnknown)
                .font(.caption)
                .help("Render unknown voxels (unexplored areas)")

            Divider()

            // Occupied color
            HStack {
                Text("Occupied Color")
                    .font(.caption)
                    .frame(width: 90, alignment: .trailing)
                ColorPicker("", selection: Binding(
                    get: { Color(red: layer.settings.octomapOccupiedR,
                                 green: layer.settings.octomapOccupiedG,
                                 blue: layer.settings.octomapOccupiedB) },
                    set: { c in
                        let ns = NSColor(c)
                        layer.settings.octomapOccupiedR = Double(ns.redComponent)
                        layer.settings.octomapOccupiedG = Double(ns.greenComponent)
                        layer.settings.octomapOccupiedB = Double(ns.blueComponent)
                    }))
                .labelsHidden()
            }

            // Free color
            HStack {
                Text("Free Color")
                    .font(.caption)
                    .frame(width: 90, alignment: .trailing)
                ColorPicker("", selection: Binding(
                    get: { Color(red: layer.settings.octomapFreeR,
                                 green: layer.settings.octomapFreeG,
                                 blue: layer.settings.octomapFreeB) },
                    set: { c in
                        let ns = NSColor(c)
                        layer.settings.octomapFreeR = Double(ns.redComponent)
                        layer.settings.octomapFreeG = Double(ns.greenComponent)
                        layer.settings.octomapFreeB = Double(ns.blueComponent)
                    }))
                .labelsHidden()
            }

            Divider()

            // Opacity
            HStack {
                Text("Opacity")
                    .font(.caption)
                    .frame(width: 90, alignment: .trailing)
                Slider(value: $layer.settings.octomapAlpha, in: 0.1...1.0, step: 0.05)
                    .frame(width: 120)
                Text(String(format: "%.0f%%", layer.settings.octomapAlpha * 100))
                    .font(.caption.monospaced())
                    .frame(width: 36, alignment: .trailing)
            }

            // Stride
            HStack {
                Text("LOD Stride")
                    .font(.caption)
                    .frame(width: 90, alignment: .trailing)
                Stepper(value: $layer.settings.octomapStrideN, in: 1...16) {
                    Text("\(layer.settings.octomapStrideN)x")
                        .font(.caption.monospaced())
                }
                .help("Render every Nth voxel — higher = faster but sparser")
            }
        }
        .padding(14)
        .frame(width: 280)
    }

    // MARK: Mesh Map settings

    private var meshMapSettingsBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Mesh Map Settings")
                .font(.subheadline.weight(.semibold))
            Divider()

            // Color tint
            HStack {
                Text("Color Tint")
                    .font(.caption)
                    .frame(width: 80, alignment: .trailing)
                ColorPicker("", selection: Binding(
                    get: { Color(red: layer.settings.meshMapR,
                                 green: layer.settings.meshMapG,
                                 blue: layer.settings.meshMapB) },
                    set: { c in
                        let ns = NSColor(c)
                        layer.settings.meshMapR = Double(ns.redComponent)
                        layer.settings.meshMapG = Double(ns.greenComponent)
                        layer.settings.meshMapB = Double(ns.blueComponent)
                    }))
                .labelsHidden()
            }

            Divider()

            // TODO: wireframe — implement as a separate ticket (Option A: triangle fill mode pass)
            Toggle("Double-Sided", isOn: $layer.settings.meshMapDoubleSided)
                .font(.caption)
                .help("Render both front and back faces of triangles")

            // Stride
            HStack {
                Text("LOD Stride")
                    .font(.caption)
                    .frame(width: 80, alignment: .trailing)
                Stepper(value: $layer.settings.meshMapStrideN, in: 1...16) {
                    Text("\(layer.settings.meshMapStrideN)x")
                        .font(.caption.monospaced())
                }
                .help("Render every Nth triangle — higher = faster but sparser")
            }
        }
        .padding(14)
        .frame(width: 280)
    }

    // MARK: Robot Model settings

    private var robotModelSettingsBody: some View {
        let links = robotModel?.links ?? []
        let meshLinks = links.filter { $0.meshKey != nil }
        let loadedCount = meshLinks.filter {
            guard let key = $0.meshKey else { return false }
            return loadedMeshKeys.contains(key)
        }.count

        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                // Title row
                HStack {
                    Text("Robot Model")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    if !links.isEmpty, let onLoadURDF {
                        Button("Reload…", action: onLoadURDF)
                            .font(.caption2)
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .help("Load a new URDF file to replace the current model")
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 12)

                if links.isEmpty {
                    // ── Empty state ──
                    VStack(spacing: 16) {
                        Image(systemName: "figure.stand")
                            .font(.system(size: 38, weight: .thin))
                            .foregroundStyle(.tertiary)

                        VStack(spacing: 4) {
                            Text("No model loaded")
                                .font(.callout.weight(.medium))
                            Text("Load a URDF file to visualize the robot's links and joints in the 3D scene.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        if let onLoadURDF {
                            Button(action: onLoadURDF) {
                                HStack(spacing: 5) {
                                    Image(systemName: "doc.badge.plus")
                                    Text("Load Robot Description…")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.regular)
                            .help("Open a URDF file to load the robot's kinematic model and meshes")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 24)

                } else {
                    // ── Status card ──
                    let allLoaded = meshLinks.isEmpty || loadedCount == meshLinks.count
                    HStack(alignment: .center, spacing: 10) {
                        Circle()
                            .fill(allLoaded ? Color.accentColor : Color.orange)
                            .frame(width: 7, height: 7)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(links.count) links")
                                .font(.caption.weight(.medium))
                            if meshLinks.isEmpty {
                                Text("Kinematic only — no visual meshes")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            } else if allLoaded {
                                Text("\(loadedCount) meshes loaded")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("\(loadedCount) of \(meshLinks.count) meshes loaded")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
                    .padding(.horizontal, 10)

                    Divider().padding(.vertical, 10)

                    // ── Appearance ──
                    VStack(alignment: .leading, spacing: 10) {
                        Text("APPEARANCE")
                            .font(.system(size: 10, weight: .medium))
                            .tracking(0.5)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 14)

                        opacityRow
                            .padding(.horizontal, 14)
                            .help("Overall transparency of the robot model")

                        HStack(spacing: 8) {
                            Text("Color Tint")
                                .font(.caption)
                                .frame(width: 72, alignment: .trailing)
                            ColorPicker("", selection: Binding(
                                get: { Color(red: layer.settings.robotModelTintR,
                                             green: layer.settings.robotModelTintG,
                                             blue: layer.settings.robotModelTintB) },
                                set: { c in
                                    let ns = NSColor(c)
                                    layer.settings.robotModelTintR = Double(ns.redComponent)
                                    layer.settings.robotModelTintG = Double(ns.greenComponent)
                                    layer.settings.robotModelTintB = Double(ns.blueComponent)
                                }))
                            .labelsHidden()
                            .help("Multiplicative tint applied to every link's material color")
                            Button("Reset") {
                                layer.settings.robotModelTintR = 1.0
                                layer.settings.robotModelTintG = 1.0
                                layer.settings.robotModelTintB = 1.0
                            }
                            .font(.caption2)
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 14)
                    }

                    Divider().padding(.vertical, 10)

                    // ── Links ──
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            HStack(spacing: 4) {
                                Text("LINKS")
                                    .font(.system(size: 10, weight: .medium))
                                    .tracking(0.5)
                                    .foregroundStyle(.secondary)
                                Text("\(links.count)")
                                    .font(.system(size: 10).monospaced())
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer()
                            Button("Show All") { layer.settings.robotModelHiddenLinks = [] }
                                .font(.caption2).buttonStyle(.plain).foregroundStyle(.secondary)
                                .help("Make all links visible")
                            Text("·").font(.caption2).foregroundStyle(.tertiary).padding(.horizontal, 3)
                            Button("Hide All") { layer.settings.robotModelHiddenLinks = Set(links.map(\.name)) }
                                .font(.caption2).buttonStyle(.plain).foregroundStyle(.secondary)
                                .help("Hide all links")
                        }
                        .padding(.horizontal, 14)
                        .padding(.bottom, 6)

                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(links, id: \.name) { link in
                                robotLinkRow(link)
                            }
                        }
                    }
                    .padding(.bottom, 10)
                }
            }
        }
        .frame(width: 300)
        .frame(maxHeight: links.isEmpty ? 280 : min(600, 280 + CGFloat(links.count) * 28))
        .fileImporter(
            isPresented: Binding(
                get: { linkForMeshPick != nil },
                set: { if !$0 { linkForMeshPick = nil } }
            ),
            allowedContentTypes: [
                UTType(filenameExtension: "stl") ?? .data,
                UTType(filenameExtension: "obj") ?? .data,
                UTType(filenameExtension: "dae") ?? .data
            ],
            allowsMultipleSelection: false
        ) { result in
            guard let linkName = linkForMeshPick else { return }
            linkForMeshPick = nil
            if case .success(let urls) = result, let url = urls.first {
                layer.settings.robotModelMeshOverrides[linkName] = url.path
                onOverrideLinkMesh?(linkName, url)
            }
        }
    }

    @ViewBuilder
    private func robotLinkRow(_ link: RobotModelCore.Link) -> some View {
        let hidden = layer.settings.robotModelHiddenLinks.contains(link.name)
        let hasMesh = link.meshKey != nil
        let meshLoaded = hasMesh && loadedMeshKeys.contains(link.meshKey ?? "")
        let meshMissing = hasMesh && !meshLoaded
        let overridePath = layer.settings.robotModelMeshOverrides[link.name]

        HStack(spacing: 0) {
            // Mesh status indicator (left gutter, 28pt)
            Group {
                if hasMesh {
                    if meshLoaded {
                        Circle()
                            .fill(overridePath != nil ? Color.accentColor : Color(red: 0.24, green: 0.83, blue: 0.5))
                            .frame(width: 5, height: 5)
                    } else {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 7))
                            .foregroundStyle(.orange)
                    }
                }
            }
            .frame(width: 28, alignment: .center)

            // Link name + subtitle
            VStack(alignment: .leading, spacing: 1) {
                Text(link.name)
                    .font(.caption.monospaced())
                    .foregroundStyle(hidden ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if !hasMesh {
                    Text("no visual")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                } else if meshMissing {
                    Text("mesh not found")
                        .font(.system(size: 9))
                        .foregroundStyle(.orange)
                } else if let path = overridePath {
                    Text(URL(filePath: path).lastPathComponent)
                        .font(.system(size: 9).monospaced())
                        .foregroundStyle(Color.accentColor)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Eye toggle (right)
            Button {
                if hidden {
                    layer.settings.robotModelHiddenLinks.remove(link.name)
                } else {
                    layer.settings.robotModelHiddenLinks.insert(link.name)
                }
            } label: {
                Image(systemName: hidden ? "eye.slash" : "eye")
                    .font(.caption2)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
                    .foregroundStyle(hidden ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.secondary))
            }
            .buttonStyle(.plain)
            .help(hidden ? "Show this link" : "Hide this link")
        }
        .padding(.vertical, 3)
        .background(hidden ? Color.primary.opacity(0.03) : Color.clear)
        .contentShape(Rectangle())
        .contextMenu {
            if hasMesh {
                Button {
                    linkForMeshPick = link.name
                } label: {
                    Label(overridePath != nil ? "Replace Override Mesh…" : "Override Mesh…",
                          systemImage: "doc.badge.arrow.up")
                }
                if overridePath != nil {
                    Button("Clear Mesh Override", role: .destructive) {
                        layer.settings.robotModelMeshOverrides.removeValue(forKey: link.name)
                    }
                }
                Divider()
            }
            if hidden {
                Button("Show Link") { layer.settings.robotModelHiddenLinks.remove(link.name) }
            } else {
                Button("Hide Link") { layer.settings.robotModelHiddenLinks.insert(link.name) }
            }
            Divider()
            Button("Reset All Mesh Overrides", role: .destructive) {
                layer.settings.robotModelMeshOverrides = [:]
            }
        }
    }

    // MARK: LaserScan settings (color, point size, decay, color mode, range filter, viz mode)

    private var laserScanSettingsBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("LaserScan Settings")
                .font(.subheadline.weight(.semibold))
            Divider()

            // Visualization mode (dots vs rays)
            LabeledContent("Visualization") {
                Picker("", selection: $layer.settings.scanVizMode) {
                    ForEach(ScanVizMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 130)
                .labelsHidden()
                .help("Dots = single points at each beam endpoint, Rays = lines from sensor origin to each endpoint")
            }

            // Color mode picker
            LabeledContent("Color Mode") {
                Picker("", selection: $layer.settings.colorMode) {
                    ForEach(LayerColorMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 130)
                .help("Flat = single color, By Distance = rainbow gradient from near (blue) to far (red), By Intensity = 5-stop gradient based on reflectance")
            }

            if layer.settings.colorMode == .flat {
                colorPickerRow(label: "Colour")
            } else if layer.settings.colorMode == .byIntensity {
                Text("Intensity range auto-detected from sensor data")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Range filter — always visible (CFG-01/02): filters beams regardless of color mode
            Divider()
            Text("Range Filter")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            LabeledContent("Min (m)") {
                Slider(value: $layer.settings.rangeMin, in: 0...50, step: 0.1)
                    .frame(width: 100)
                    .help("Minimum beam distance to display — filter out noise near the sensor")
                Text(String(format: "%.1f", layer.settings.rangeMin))
                    .font(.caption.monospaced())
                    .frame(width: 44, alignment: .trailing)
            }
            LabeledContent("Max (m)") {
                Slider(value: $layer.settings.rangeMax, in: 0.5...100, step: 0.5)
                    .frame(width: 100)
                    .help("Maximum beam distance to display — crop far-away beams")
                Text(String(format: "%.1f", layer.settings.rangeMax))
                    .font(.caption.monospaced())
                    .frame(width: 44, alignment: .trailing)
            }

            Divider()
            opacityRow
            pointSizeRow
            decayRow
        }
        .padding(14)
        .frame(width: 280)
    }

    // MARK: PointCloud2 settings

    private var pointCloud2SettingsBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PointCloud2 Settings")
                .font(.subheadline.weight(.semibold))
            Divider()

            // Color by picker
            LabeledContent("Color By") {
                Picker("", selection: $layer.settings.pc2ColorMode) {
                    ForEach(PC2ColorMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 130)
                .help("Flat = single color, By Height = color by Z-axis height (rainbow gradient), By Channel = color per channel in the point cloud")
            }

            if layer.settings.pc2ColorMode == .flat {
                colorPickerRow(label: "Colour")
            } else if layer.settings.pc2ColorMode == .byHeight {
                LabeledContent("Height Min") {
                    Slider(value: $layer.settings.pc2HeightMin, in: -5...5, step: 0.1)
                        .frame(width: 100)
                        .help("Minimum Z value for the height color gradient (meters)")
                    Text(String(format: "%.1f m", layer.settings.pc2HeightMin))
                        .font(.caption.monospaced())
                        .frame(width: 44, alignment: .trailing)
                }
                LabeledContent("Height Max") {
                    Slider(value: $layer.settings.pc2HeightMax, in: -5...10, step: 0.1)
                        .frame(width: 100)
                        .help("Maximum Z value for the height color gradient (meters)")
                    Text(String(format: "%.1f m", layer.settings.pc2HeightMax))
                        .font(.caption.monospaced())
                        .frame(width: 44, alignment: .trailing)
                }
            }

            // Stride
            LabeledContent("Stride") {
                Picker("", selection: $layer.settings.pc2StrideN) {
                    Text("1 (all)").tag(1)
                    Text("2 (½)").tag(2)
                    Text("4 (¼)").tag(4)
                    Text("8 (⅛)").tag(8)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 80)
                .help("Downsample factor — 1 shows every point, 2 shows half, 4 shows quarter. Higher stride = better performance on dense clouds")
            }

            Divider()
            opacityRow
            pointSizeRow
            decayRow
        }
        .padding(14)
        .frame(width: 280)
    }

    // MARK: Odometry settings

    private var odometrySettingsBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Odometry Settings")
                .font(.subheadline.weight(.semibold))
            Divider()

            Toggle("Show Trail", isOn: $layer.settings.showOdomTrail)
                .font(.caption)
                .help("Draw a trail of past poses behind the robot — shows where it has been")

            if layer.settings.showOdomTrail {
                LabeledContent("Trail Length") {
                    Picker("", selection: $layer.settings.odomTrailLength) {
                        Text("10").tag(10)
                        Text("50").tag(50)
                        Text("100").tag(100)
                        Text("500").tag(500)
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 80)
                    .help("Number of past poses to keep in the trail")
                }

                HStack {
                    Text("Trail Color")
                        .font(.caption)
                        .frame(width: 80, alignment: .trailing)
                    ColorPicker("", selection: Binding(
                        get: { Color(red: layer.settings.odomTrailR,
                                     green: layer.settings.odomTrailG,
                                     blue: layer.settings.odomTrailB) },
                        set: { c in
                            let ns = NSColor(c)
                            layer.settings.odomTrailR = Double(ns.redComponent)
                            layer.settings.odomTrailG = Double(ns.greenComponent)
                            layer.settings.odomTrailB = Double(ns.blueComponent)
                        }))
                    .labelsHidden()
                    .help("Color of the odometry trail path")
                }
            }

            Divider()
            opacityRow
            pointSizeRow
            decayRow
        }
        .padding(14)
        .frame(width: 280)
    }

    // MARK: PoseStamped settings

    private var poseStampedSettingsBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PoseStamped Settings")
                .font(.subheadline.weight(.semibold))
            Divider()
            colorPickerRow(label: "Arrow Color")
            opacityRow
            pointSizeRow
        }
        .padding(14)
        .frame(width: 280)
    }

    // MARK: MarkerArray settings

    private var markerArraySettingsBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("MarkerArray Settings")
                .font(.subheadline.weight(.semibold))
            Divider()

            LabeledContent("NS Filter") {
                TextField("all namespaces", text: $layer.settings.markerNamespaceFilter)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption.monospaced())
                    .frame(width: 130)
                    .help("Filter markers by ROS namespace — leave blank to show all")
            }

            Divider()
            colorPickerRow(label: "Colour")
            opacityRow
            pointSizeRow
            decayRow
        }
        .padding(14)
        .frame(width: 280)
    }

    // MARK: Path settings

    private var pathSettingsBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Path Settings")
                .font(.subheadline.weight(.semibold))
            Divider()
            colorPickerRow(label: "Colour")
            opacityRow

            Divider()
            Toggle("Show Waypoints", isOn: $layer.settings.showPathWaypoints)
                .font(.caption)
                .help("Display circular markers along the path at regular intervals")

            if layer.settings.showPathWaypoints {
                LabeledContent("Every N Poses") {
                    Stepper(value: $layer.settings.pathWaypointEveryN, in: 1...20) {
                        Text("\(layer.settings.pathWaypointEveryN)")
                            .font(.caption.monospaced())
                            .frame(width: 28, alignment: .trailing)
                    }
                    .help("Show a waypoint marker every N poses in the path")
                }
                LabeledContent("Waypoint Size") {
                    Slider(value: $layer.settings.pathWaypointSize, in: 2...10, step: 0.5)
                        .frame(width: 100)
                        .help("Size of each waypoint marker (points)")
                    Text(String(format: "%.1f", layer.settings.pathWaypointSize))
                        .font(.caption.monospaced())
                        .frame(width: 32, alignment: .trailing)
                }
            }
        }
        .padding(14)
        .frame(width: 280)
    }

    // MARK: Generic settings (image, etc.)

    private var genericSettingsBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Layer Settings")
                .font(.subheadline.weight(.semibold))
            Divider()
            colorPickerRow(label: "Colour")
            opacityRow
            if layer.type.isPointBased {
                pointSizeRow
                decayRow
            }
        }
        .padding(14)
        .frame(width: 280)
    }

    // MARK: Shared row helpers

    @ViewBuilder
    private func colorPickerRow(label: String) -> some View {
        ColorPicker(label, selection: Binding(
            get: { layer.settings.swiftUIColor },
            set: { newColor in
                if let resolved = newColor.resolve(in: .init()) {
                    layer.settings.r = Double(resolved.red)
                    layer.settings.g = Double(resolved.green)
                    layer.settings.b = Double(resolved.blue)
                    layer.settings.opacity = Double(resolved.opacity)
                }
            }
        ))
        .labelsHidden()
    }

    private var opacityRow: some View {
        LabeledContent("Opacity") {
            Slider(value: $layer.settings.opacity, in: 0...1, step: 0.05)
                .frame(width: 120)
                .help("Transparency of this layer — lower to see layers behind")
            Text("\(Int(layer.settings.opacity * 100))%")
                .font(.caption.monospaced())
                .frame(width: 32, alignment: .trailing)
        }
    }

    private var pointSizeRow: some View {
        LabeledContent("Point size") {
            Slider(value: Binding(
                get: { Double(layer.settings.pointSize) },
                set: { layer.settings.pointSize = Float($0) }
            ), in: 1...10, step: 0.5)
            .frame(width: 120)
            .help("Size of each rendered point in the 3D view (points)")
            Text(String(format: "%.1f", layer.settings.pointSize))
                .font(.caption.monospaced())
                .frame(width: 32, alignment: .trailing)
        }
    }

    private var decayRow: some View {
        LabeledContent("Decay (s)") {
            Slider(value: $layer.settings.decaySeconds, in: 0...10, step: 0.5)
                .frame(width: 120)
                .help("Fade out old points over time — 0 = keep all points, higher = faster fadeout")
            Text(layer.settings.decaySeconds == 0
                 ? "off"
                 : String(format: "%.1fs", layer.settings.decaySeconds))
                .font(.caption.monospaced())
                .frame(width: 32, alignment: .trailing)
        }
    }
}

// MARK: - Change Topic Sheet (NF-1)

/// Allows picking a replacement topic for an existing layer without removing and re-adding it.
private struct ChangeTopicSheet: View {
    let currentLayer: DisplayLayer
    let availableTopics: [TopicDescriptor]
    let onSelect: (String) -> Void
    let onCancel: () -> Void

    @State private var searchText = ""

    /// Topics compatible with the current layer type.
    private var compatibleTopics: [(TopicDescriptor, LayerType)] {
        availableTopics.compactMap { td -> (TopicDescriptor, LayerType)? in
            guard let type = LayerType.detect(from: td.schemaName) else { return nil }
            // Show only topics matching the same layer type
            guard type == currentLayer.type else { return nil }
            // Exclude the current topic from the list
            guard td.name != currentLayer.topic else { return nil }
            return (td, type)
        }
        .filter {
            searchText.isEmpty
            || $0.0.name.localizedCaseInsensitiveContains(searchText)
        }
        .sorted { $0.0.name < $1.0.name }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Change Topic")
                        .font(.headline)
                    Text("Current: \(currentLayer.topic)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 8)

            Divider()

            TextField("Search topics…", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            if compatibleTopics.isEmpty {
                Text(availableTopics.isEmpty
                     ? "No robot connected"
                     : "No compatible topics available")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(12)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(compatibleTopics, id: \.0.name) { td, _ in
                            Button {
                                onSelect(td.name)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: currentLayer.type.systemImage)
                                        .font(.caption)
                                        .foregroundStyle(Color.accentColor)
                                        .frame(width: 18)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(td.name)
                                            .font(.caption.monospaced())
                                            .lineLimit(2)
                                            .fixedSize(horizontal: false, vertical: true)
                                        Text(td.schemaName)
                                            .font(.caption2.monospaced())
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "arrow.right.circle")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .frame(width: 320, height: 400)
    }
}

// MARK: - Color resolve helper

private extension Color {
    func resolve(in environment: EnvironmentValues) -> (red: CGFloat, green: CGFloat, blue: CGFloat, opacity: CGFloat)? {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard let ns = NSColor(self).usingColorSpace(.deviceRGB) else { return nil }
        ns.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b, a)
    }
}
