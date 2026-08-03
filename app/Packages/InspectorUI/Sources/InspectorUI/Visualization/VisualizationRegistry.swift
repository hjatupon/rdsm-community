import SwiftUI
import ChartingCore

// MARK: - Viz picker bar seam (open-core)

/// Everything the (Pro) visualization-picker bar needs, supplied by InspectorView.
/// The bar itself (name/badge/reset + "Change" button + picker modal) is injected by
/// the paid InspectorProViews package; the free build shows no picker bar.
@MainActor
public struct VizPickerBarContext {
    public let topicName: String
    public let schemaName: String
    public let currentVizID: String?
    public let makeSnapshot: @MainActor () -> VisualizationSnapshot
    /// nil = reset to auto-detected; otherwise set an override id.
    public let onSelect: (String?) -> Void

    public init(topicName: String,
                schemaName: String,
                currentVizID: String?,
                makeSnapshot: @escaping @MainActor () -> VisualizationSnapshot,
                onSelect: @escaping (String?) -> Void) {
        self.topicName = topicName
        self.schemaName = schemaName
        self.currentVizID = currentVizID
        self.makeSnapshot = makeSnapshot
        self.onSelect = onSelect
    }
}

// MARK: - VisualizationRegistry

/// Injectable catalog of inspector visualizations.
///
/// The registry ships with **only** the raw JSON tree built in. Every other
/// visualization is contributed at launch via ``register(_:make:)`` — the app
/// target decides which visualizations to install. In the open-core split, the
/// free (Community) build registers nothing extra (raw JSON only), while the
/// paid (Pro) build calls ``registerStandardVisualizations()`` to add the full
/// set. See `StandardVisualizations.swift`.
///
/// Descriptors are pure data (Sendable). Rendering is a stored `@MainActor`
/// closure returning a type-erased view.
@MainActor
public final class VisualizationRegistry {

    public static let shared = VisualizationRegistry()

    /// A registered visualization: its descriptor plus a view factory.
    struct Entry {
        let descriptor: VisualizationDescriptor
        let make: @MainActor (VisualizationSnapshot) -> AnyView
    }

    private var entries: [String: Entry] = [:]
    private var order: [String] = []

    private init() {
        // Built-in (always available, including the free Community build):
        // only the raw JSON tree. Everything else is injected via register(_:make:).
        register(.init(id: "raw.jsonTree",
                       name: "JSON Tree",
                       tagline: "Always-expanded field explorer",
                       category: .data, sfSymbol: "curlybraces",
                       compatibleSchemas: [], compatibleKeywords: [],
                       recommendationScore: 10)) { snapshot in
            if snapshot.jsonRoots.isEmpty {
                AnyView(Self.vizPlaceholder("No data yet", icon: "curlybraces"))
            } else {
                AnyView(JSONTreeView(roots: snapshot.jsonRoots, expandedArrayIDs: .constant([])))
            }
        }
    }

    // MARK: - Registration

    /// Register (or replace) a visualization. Registration order is preserved
    /// for `all`-based queries. Safe to call multiple times.
    public func register(_ descriptor: VisualizationDescriptor,
                         make: @escaping @MainActor (VisualizationSnapshot) -> AnyView) {
        if entries[descriptor.id] == nil { order.append(descriptor.id) }
        entries[descriptor.id] = Entry(descriptor: descriptor, make: make)
    }

    // MARK: - Catalog

    /// All registered descriptors, in registration order.
    var all: [VisualizationDescriptor] { order.compactMap { entries[$0]?.descriptor } }

    // MARK: - Query API

    public func descriptor(id: String) -> VisualizationDescriptor? {
        entries[id]?.descriptor
    }

    /// Descriptors with score ≥ 50 for the given schema, sorted descending.
    public func recommended(for schema: String) -> [VisualizationDescriptor] {
        all.filter { $0.score(for: schema) >= 50 }
           .sorted { $0.score(for: schema) > $1.score(for: schema) }
    }

    /// All descriptors that can render the given schema.
    public func compatible(for schema: String) -> [VisualizationDescriptor] {
        all.filter { $0.isCompatible(with: schema) }
    }

    /// Full-text search across name, tagline, category. Always-compatible entries always included.
    public func search(_ query: String, schema: String) -> [VisualizationDescriptor] {
        let q = query.lowercased()
        return all.filter { desc in
            desc.isCompatible(with: schema) &&
            (q.isEmpty ||
             desc.name.lowercased().contains(q) ||
             desc.tagline.lowercased().contains(q) ||
             desc.category.rawValue.lowercased().contains(q))
        }
    }

    /// The descriptor ID that matches what RenderKindResolver would pick automatically.
    /// Falls back to `raw.jsonTree` when the mapped visualization isn't registered
    /// (e.g. the free Community build, which ships raw JSON only).
    public func defaultID(for schema: String) -> String {
        let kind = RenderKindResolver().resolve(schemaName: schema)
        let id = descriptorID(for: kind)
        return entries[id] != nil ? id : "raw.jsonTree"
    }

    private func descriptorID(for kind: RenderKind) -> String {
        switch kind {
        case .laserScan:       return "laser.polar"
        case .occupancyGrid:   return "nav.occupancyGrid"
        case .odometry:        return "nav.odometry"
        case .imu:             return "sensor.imu"
        case .jointState:      return "sensor.jointState"
        case .twist:           return "geometry.twist"
        case .diagnosticArray: return "diagnostic.array"
        case .batteryState:    return "sensor.battery"
        case .rangeGauge:      return "sensor.range"
        case .image:           return "sensor.image"
        case .logMessage:      return "rcl.log"
        case .boolean:         return "std.bool"
        case .stringValue:     return "std.string"
        case .numericScalar:   return "numeric.lineChart"
        case .tfTree:          return "raw.jsonTree"
        case .jsonTree:        return "raw.jsonTree"
        }
    }

    // MARK: - View rendering

    /// Renders the visualization identified by `id` from a frozen snapshot.
    /// Called both for live inspector content (snapshot updated each message)
    /// and for static preview cards inside the picker modal.
    /// Falls back to the raw JSON tree when `id` isn't registered.
    public func makeView(id: String, snapshot: VisualizationSnapshot) -> AnyView {
        if let entry = entries[id] { return entry.make(snapshot) }
        if let json = entries["raw.jsonTree"] { return json.make(snapshot) }
        return AnyView(Self.vizPlaceholder("Unknown visualization", icon: "questionmark.circle"))
    }

    // MARK: - Viz picker bar (Pro-injected)

    private var vizPickerBarBuilder: (@MainActor (VizPickerBarContext) -> AnyView)?

    /// Register the (Pro) visualization-picker bar. Free build never calls this.
    public func registerVizPickerBar(_ build: @escaping @MainActor (VizPickerBarContext) -> AnyView) {
        vizPickerBarBuilder = build
    }

    /// Build the picker bar, or nil when no Pro visualizations are installed.
    public func makeVizPickerBar(context: VizPickerBarContext) -> AnyView? {
        vizPickerBarBuilder?(context)
    }

    @ViewBuilder
    public static func vizPlaceholder(_ label: String, icon: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.largeTitle).foregroundStyle(.secondary)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
