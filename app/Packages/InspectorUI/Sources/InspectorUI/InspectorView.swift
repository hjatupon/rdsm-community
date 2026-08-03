import SwiftUI
import Transport
import TopicStore
import MessageRegistry

/// Type-aware message inspector.
///
/// Dispatches to the appropriate sub-view based on the schema name:
/// - `sensor_msgs/…/Image`        → ``ImageInspectorView``
/// - `std_msgs/…/Float64` etc.    → ``NumericChartView`` (time-series chart)
/// - `std_msgs/…/Bool`            → ``BoolIndicatorView``
/// - `std_msgs/…/String`          → ``StringValueView``
/// - `rcl_interfaces/…/Log`       → ``LogListView``
/// - `sensor_msgs/…/Range`        → ``RangeGaugeView``
/// - `sensor_msgs/…/BatteryState` → ``BatteryStateView``
/// - `tf2_msgs/…/TFMessage`       → TF tree (via `tfTreeContent` view builder)
/// - Everything else              → ``JSONTreeView``
public struct InspectorView<TFContent: View>: View {
    @State private var viewModel: InspectorViewModel
    @State private var showRaw = false
    @State private var isPinned: Bool = UserDefaults.standard.bool(forKey: "inspector.pinned")

    private let topic: TopicDescriptor
    @ViewBuilder private let tfTreeContent: () -> TFContent

    // RAW-01: Freeze
    @State private var rawFrozen: Bool = false
    @State private var frozenRoots: [FieldNode] = []
    @State private var frozenMsgCount: UInt64 = 0

    // RAW-05: Search
    @State private var rawSearch: String = ""
    @FocusState private var searchFocused: Bool

    // RAW-06: Expand-all / Collapse-all (tracks which large-array node IDs are fully expanded)
    @State private var expandedArrayIDs: Set<String> = []

    /// Mirrors `perf.inspectorThrottleSeconds` from UserDefaults so that changes in
    /// Performance Settings apply live without requiring a reconnect.
    @AppStorage("perf.inspectorThrottleSeconds") private var perfThrottleSec: Double = 0.0

    public init(store: TopicStore,
                registry: any MessageRegistry,
                topic: TopicDescriptor,
                @ViewBuilder tfTreeContent: @escaping () -> TFContent = { EmptyView() }) {
        _viewModel = State(initialValue: InspectorViewModel(
            store: store, registry: registry, topic: topic))
        self.topic = topic
        self.tfTreeContent = tfTreeContent
    }

    private var isTFContent: Bool {
        viewModel.renderKind == .tfTree
    }

    public var body: some View {
        VStack(spacing: 0) {
            if !isTFContent {
                header
                Divider()
                throttleBar
                Divider()
                // Viz-picker bar is a Pro surface (injected). Absent in the free build.
                if let bar = VisualizationRegistry.shared.makeVizPickerBar(context: vizPickerBarContext) {
                    bar
                    Divider()
                }
            }
            content
        }
        .task { await viewModel.startSubscription() }
        .onDisappear { viewModel.stopSubscription() }
        .onAppear { viewModel.setThrottle(perfThrottleSec) }
        .onChange(of: perfThrottleSec) { _, v in viewModel.setThrottle(v) }
    }

    // MARK: - Sub-views

    private var vizPickerBarContext: VizPickerBarContext {
        VizPickerBarContext(
            topicName: topic.name,
            schemaName: topic.schemaName,
            currentVizID: viewModel.vizOverrideID,
            makeSnapshot: { viewModel.snapshotState() },
            onSelect: { selectedID in
                let defaultID = VisualizationRegistry.shared.defaultID(for: topic.schemaName)
                if let id = selectedID, id != defaultID {
                    viewModel.setVizOverride(id)
                } else {
                    viewModel.resetVizOverride()
                }
            })
    }

    /// Discrete throttle options surfaced in the dropdown.
    private var throttleOptions: [(label: String, seconds: Double)] {
        [
        ("Live",   0.0),
        ("0.1 s",  0.1),
        ("0.25 s", 0.25),
        ("0.5 s",  0.5),
        ("1 s",    1.0),
        ("2 s",    2.0),
        ("5 s",    5.0),
        ("10 s",   10.0),
        ]
    }

    /// Returns the option whose value is closest to `seconds`.
    /// Used so set arbitrary values round-trip to the nearest tag.
    private func nearestOption(for seconds: Double) -> Double {
        guard seconds > 0 else { return 0 }
        return throttleOptions
            .min(by: { abs($0.seconds - seconds) < abs($1.seconds - seconds) })!
            .seconds
    }

    private var throttleBar: some View {
        HStack(spacing: 8) {
            // Pause / Resume toggle
            Button {
                viewModel.setPaused(!viewModel.isPaused)
            } label: {
                Label(viewModel.isPaused ? "Resume" : "Pause",
                      systemImage: viewModel.isPaused ? "play.fill" : "pause.fill")
                    .font(.caption)
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .help(viewModel.isPaused ? "Resume live updates" : "Pause display (subscription stays active)")
            .foregroundStyle(viewModel.isPaused ? .orange : .secondary)
            .accessibilityLabel(viewModel.isPaused ? "Resume" : "Pause")

            // Rate dropdown — replaces the old slider
            Picker("Sample rate", selection: Binding(
                get: { nearestOption(for: viewModel.throttleSeconds) },
                set: { viewModel.setThrottle($0) }
            )) {
                ForEach(throttleOptions, id: \.seconds) { option in
                    Text(option.label).tag(option.seconds)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .font(.caption)
            .help("Sample rate: how often the Inspector panel updates. Live = every message.")

            Spacer()

            // Visual / Raw toggle — always shown (B3-14)
            Picker("View mode", selection: $showRaw) {
                Text("Visual").tag(false)
                Text("Raw").tag(true)
            }
            .pickerStyle(.segmented)
            .fixedSize()
            .help("Switch between the specialized visualization and raw JSON data")

            // Reset
            Button("Reset") { viewModel.resetThrottling() }
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundStyle(.secondary)
                .help("Return to live, full-speed display")
                .disabled(!viewModel.isPaused && viewModel.throttleSeconds == 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(topic.name)
                    .font(.headline.monospaced())
                    .lineLimit(1)
                Text(topic.schemaName)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if viewModel.isSubscribed {
                    Label(String(format: "%.1f Hz", viewModel.hz),
                          systemImage: "waveform")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Label(viewModel.subscriptionError ?? "Connecting…",
                          systemImage: "circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("\(viewModel.messageCount) msgs")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            // Pin button — locks the Inspector to the current topic (B2-06)
            Button {
                isPinned.toggle()
                UserDefaults.standard.set(isPinned, forKey: "inspector.pinned")
            } label: {
                Image(systemName: isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 13))
                    .foregroundStyle(isPinned ? Color(red: 0.18, green: 0.73, blue: 0.69) : .secondary)
            }
            .buttonStyle(.borderless)
            .help(isPinned
                  ? "Pinned — topic browser clicks won't change the Inspector. Click to unpin."
                  : "Pin Inspector to this topic — topic browser clicks won't change the Inspector")
            .padding(.leading, 4)
        }
        .padding()
        .background(.bar)
    }

    @ViewBuilder
    private var rawView: some View {
        if viewModel.jsonRoots.isEmpty && !viewModel.isSubscribed {
            placeholder("Waiting for message…", icon: "dot.radiowaves.left.and.right")
        } else {
            VStack(spacing: 0) {
                // RAW toolbar: Copy JSON + Freeze + Expand All / Collapse All
                HStack(spacing: 8) {
                    Button {
                        if let payload = viewModel.latestPayload,
                           let json = try? JSONSerialization.jsonObject(with: payload),
                           let pretty = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted),
                           let str = String(data: pretty, encoding: .utf8) {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(str, forType: .string)
                        }
                    } label: {
                        Label("Copy JSON", systemImage: "doc.on.clipboard")
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help("Copy the entire JSON message to clipboard")

                    Divider().frame(height: 12)

                    // RAW-06: Expand All large arrays
                    Button {
                        let ids = collectArrayIDs(from: rawFrozen ? frozenRoots : viewModel.jsonRoots)
                        expandedArrayIDs = ids
                    } label: {
                        Image(systemName: "chevron.down.2")
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help("Expand all large arrays")

                    // RAW-06: Collapse All large arrays
                    Button {
                        expandedArrayIDs = []
                    } label: {
                        Image(systemName: "chevron.up.2")
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help("Collapse all large arrays")

                    Divider().frame(height: 12)

                    // RAW-01: Freeze toggle
                    Button {
                        rawFrozen.toggle()
                        if !rawFrozen {
                            frozenRoots = viewModel.jsonRoots
                            frozenMsgCount = viewModel.messageCount
                        }
                    } label: {
                        Label(rawFrozen ? "Frozen" : "Freeze",
                              systemImage: rawFrozen ? "snowflake" : "pause.rectangle")
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .foregroundStyle(rawFrozen ? .orange : .secondary)
                    .help(rawFrozen ? "Click to unfreeze and resume live updates" : "Freeze the tree at the current message")

                    if rawFrozen {
                        Text("msg #\(frozenMsgCount)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.orange)
                    }

                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(.bar)
                Divider()

                // RAW-05: Search bar
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search fields…", text: $rawSearch)
                        .textFieldStyle(.plain)
                        .font(.system(.caption, design: .monospaced))
                        .focused($searchFocused)
                        .help("Search JSON field names or values — matches are highlighted in the tree")
                    if !rawSearch.isEmpty {
                        let matchCount = countMatches(
                            in: rawFrozen ? frozenRoots : viewModel.jsonRoots,
                            query: rawSearch)
                        Text("\(matchCount) results")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button(action: { rawSearch = "" }) {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .help("Clear search")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(.windowBackgroundColor).opacity(0.5))
                Divider()

                // RAW-07: Message timestamp
                if let ts = viewModel.latestTimestamp {
                    HStack {
                        Text("Received: \(ts, format: .dateTime.hour().minute().second())")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 3)
                    .background(Color(.windowBackgroundColor).opacity(0.3))
                    Divider()
                }

                JSONTreeView(roots: rawFrozen ? frozenRoots : viewModel.jsonRoots,
                             searchQuery: rawSearch,
                             expandedArrayIDs: $expandedArrayIDs)
            }
            // RAW-01: sync frozen roots when not frozen — watch messageCount (UInt64: Equatable)
            .onChange(of: viewModel.messageCount) { _, _ in
                if !rawFrozen {
                    frozenRoots = viewModel.jsonRoots
                    frozenMsgCount = viewModel.messageCount
                }
            }
        }
    }

    // MARK: - RAW helpers

    private func countMatches(in roots: [FieldNode], query: String) -> Int {
        guard !query.isEmpty else { return 0 }
        return roots.reduce(0) { $0 + countMatchesInNode($1, query: query) }
    }

    private func countMatchesInNode(_ node: FieldNode, query: String) -> Int {
        var count = 0
        if node.key.localizedCaseInsensitiveContains(query) ||
           node.displayValue.localizedCaseInsensitiveContains(query) {
            count += 1
        }
        count += node.children.reduce(0) { $0 + countMatchesInNode($1, query: query) }
        return count
    }

    private func collectArrayIDs(from roots: [FieldNode]) -> Set<String> {
        var ids = Set<String>()
        for node in roots {
            collectArrayIDsInNode(node, into: &ids)
        }
        return ids
    }

    private func collectArrayIDsInNode(_ node: FieldNode, into ids: inout Set<String>) {
        if node.displayValue.hasPrefix("[") && node.children.count > 8 {
            ids.insert(node.id)
        }
        for child in node.children {
            collectArrayIDsInNode(child, into: &ids)
        }
    }

    @ViewBuilder
    private var content: some View {
        if showRaw {
            rawView
        } else if viewModel.renderKind == .tfTree {
            // Basic TF tree stays in the shell (Core): summary + Open TF Universe + tree.
            tfTreeVisual
        } else {
            // All other visualizations come from the registry. In the free build only
            // the raw JSON tree is registered, so non-jsonTree kinds fall back to it;
            // the paid build registers the full purpose-built + generic set.
            let id = viewModel.vizOverrideID ?? VisualizationRegistry.shared.defaultID(for: topic.schemaName)
            VisualizationRegistry.shared.makeView(id: id, snapshot: viewModel.snapshotState())
        }
    }

    @ViewBuilder
    private var tfTreeVisual: some View {
        VStack(spacing: 8) {
            // Summary card
            VStack(spacing: 6) {
                Label("TF Tree", systemImage: "move.3d")
                    .font(.headline)
                if viewModel.tfSummary.hasData {
                    let s = viewModel.tfSummary
                    HStack {
                        statBlock("\(s.frameCount)", "Frames")
                        statBlock("\(s.rootCount)", "Roots")
                        statBlock("\(s.edgeCount)", "Edges")
                    }
                    HStack {
                        statBlock(String(format: "%.1f Hz", s.avgHz), "Avg Rate")
                        statBlock("\(s.staleCount)", "Stale")
                    }
                    if !s.roots.isEmpty {
                        Text("Roots: " + s.roots.joined(separator: ", "))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                } else {
                    Text("Waiting for TF messages…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))

            // Open TF Universe button
            Button {
                NotificationCenter.default.post(
                    name: Notification.Name("com.jatupon.ros2studio.tfUniverseRequested"), object: nil)
                NotificationCenter.default.post(
                    name: Notification.Name("com.jatupon.ros2studio.openPanel"), object: "tf")
            } label: {
                Label("Open TF Universe", systemImage: "move.3d")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            .controlSize(.large)

            Divider()

            // Existing TF tree content below
            tfTreeContent()
                .frame(maxHeight: .infinity)
        }
        .padding(8)
    }

    @ViewBuilder
    private func statBlock(_ value: String, _ label: String) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(.title3, design: .monospaced))
                .fontWeight(.semibold)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func placeholder(_ text: String, icon: String) -> some View {
        ContentUnavailableView(text, systemImage: icon)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}


