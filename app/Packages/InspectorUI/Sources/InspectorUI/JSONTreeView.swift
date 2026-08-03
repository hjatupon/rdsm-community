import SwiftUI
import AppKit

/// Always-expanded JSON tree built from ``FieldNode`` — shows any decoded message.
///
/// Uses a plain ScrollView+VStack instead of List(children:) so nodes stay
/// expanded across message updates. List tracks expand/collapse by node id —
/// since each message rebuild creates new UUIDs, every node would reset to
/// collapsed on every incoming message.
public struct JSONTreeView: View {
    let roots: [FieldNode]
    var searchQuery: String = ""
    /// When non-nil, large-array "show all" state is controlled by the shared set.
    @Binding var expandedArrayIDs: Set<String>

    /// Full memberwise init — used within InspectorUI where roots and binding are known.
    init(roots: [FieldNode], searchQuery: String = "", expandedArrayIDs: Binding<Set<String>>) {
        self.roots = roots
        self.searchQuery = searchQuery
        self._expandedArrayIDs = expandedArrayIDs
    }

    /// Convenience init for use in ServiceCallUI and other packages — builds the tree
    /// directly from raw JSON `Data`. The binding is backed by an internal constant
    /// so "show all" toggle is a no-op (fine for one-shot service responses).
    public init(json: Data) {
        self.roots = FieldNode.fromJSON(json)
        self._expandedArrayIDs = .constant([])
    }

    public var body: some View {
        if roots.isEmpty {
            Text("(empty message)")
                .foregroundStyle(.secondary)
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(filteredRoots) { node in
                        NodeTreeView(node: node, depth: 0,
                                     searchQuery: searchQuery,
                                     expandedArrayIDs: $expandedArrayIDs)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var filteredRoots: [FieldNode] {
        guard !searchQuery.isEmpty else { return roots }
        return roots.filter { $0.matches(searchQuery) }
    }
}

// MARK: - Value color helper

private func valueColor(for displayValue: String) -> Color {
    if displayValue == "∞" { return .red }
    if displayValue == "true" { return .green }
    if displayValue == "false" { return .orange }
    if displayValue == "null" || displayValue == "<null>" { return .secondary }
    if displayValue.hasPrefix("\"") { return .orange }
    if displayValue.hasPrefix("{") || displayValue.hasPrefix("[") { return .secondary }
    // Check numeric
    let stripped = displayValue.trimmingCharacters(in: .whitespaces)
    if Double(stripped) != nil { return Color(red: 0.18, green: 0.73, blue: 0.69) }
    return .secondary
}

private func isNullValue(_ displayValue: String) -> Bool {
    displayValue == "∞"
}

// MARK: - NodeTreeView

private struct NodeTreeView: View {
    let node: FieldNode
    let depth: Int
    let searchQuery: String
    @Binding var expandedArrayIDs: Set<String>

    @State private var flashCopy: Bool = false

    private static let truncateThreshold = 8
    private static let previewCount = 3

    private var showAllChildren: Bool {
        expandedArrayIDs.contains(node.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            rowView
            if showAllChildren, let stats = node.arraySummary {
                // Sticky stats row — shown as first child when array is fully expanded
                HStack(spacing: 8) {
                    Spacer().frame(width: CGFloat(depth + 1) * 16)
                    Text(stats)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.vertical, 2)
            }
            childrenView
        }
    }

    private var rowView: some View {
        HStack(spacing: 6) {
            if depth > 0 {
                Spacer().frame(width: CGFloat(depth) * 16)
            }
            Text(node.key)
                .font(.body.monospaced())
                .foregroundStyle(.primary)
            Spacer()
            // Show array summary as subtitle when collapsed and summary exists
            if let summary = node.arraySummary, !showAllChildren {
                Text(summary)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            valueText(node.displayValue, isLeaf: node.isLeaf)
        }
        .padding(.vertical, 2)
        .background(flashCopy ? Color(red: 0.18, green: 0.73, blue: 0.69).opacity(0.25) : Color.clear)
        .animation(.easeOut(duration: 0.3), value: flashCopy)
        .contentShape(Rectangle())
        .onTapGesture {
            // Single-click copies the field path and flashes row
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(node.id, forType: .string)
            flashCopy = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                flashCopy = false
            }
        }
        .contextMenu {
            if node.isLeaf {
                Button("Copy Value") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(node.displayValue, forType: .string)
                }
                Button("Copy Field Path") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(node.id, forType: .string)
                }
            } else {
                Button("Copy Field Path") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(node.id, forType: .string)
                }
            }
        }
    }

    @ViewBuilder
    private func valueText(_ display: String, isLeaf: Bool) -> some View {
        if display == "∞" {
            Text(display)
                .font(.body.monospaced())
                .foregroundStyle(Color.red)
                .italic()
                .lineLimit(1)
                .help("rosbridge encodes ROS infinity/NaN as JSON null")
        } else if display == "true" {
            Text(display)
                .font(.body.monospaced())
                .foregroundStyle(Color.green)
                .lineLimit(1)
        } else if display == "false" {
            Text(display)
                .font(.body.monospaced())
                .foregroundStyle(Color.orange)
                .lineLimit(1)
        } else if display.hasPrefix("\"") {
            Text(display)
                .font(.body.monospaced())
                .foregroundStyle(Color.orange)
                .lineLimit(1)
        } else if display.hasPrefix("{") || display.hasPrefix("[") {
            Text(display)
                .font(.body.monospaced())
                .foregroundStyle(Color.secondary)
                .lineLimit(1)
        } else {
            // Number or fallback — check if numeric
            let stripped = display.trimmingCharacters(in: .whitespaces)
            let isNumeric = Double(stripped) != nil
            Text(display)
                .font(.body.monospaced())
                .foregroundStyle(isNumeric ? Color(red: 0.18, green: 0.73, blue: 0.69) : Color.secondary)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var childrenView: some View {
        let children = node.children
        let isLargeArray = node.displayValue.hasPrefix("[") && children.count > Self.truncateThreshold

        if isLargeArray {
            let preview = Array(children.prefix(Self.previewCount))
            ForEach(preview) { child in
                if searchQuery.isEmpty || child.matches(searchQuery) {
                    NodeTreeView(node: child, depth: depth + 1,
                                 searchQuery: searchQuery,
                                 expandedArrayIDs: $expandedArrayIDs)
                }
            }

            if showAllChildren {
                let rest = Array(children.dropFirst(Self.previewCount))
                ForEach(rest) { child in
                    if searchQuery.isEmpty || child.matches(searchQuery) {
                        NodeTreeView(node: child, depth: depth + 1,
                                     searchQuery: searchQuery,
                                     expandedArrayIDs: $expandedArrayIDs)
                    }
                }
                expandToggleRow(label: "▼ Show fewer", depth: depth)
            } else {
                let hidden = children.count - Self.previewCount
                expandToggleRow(label: "▶ Show all \(children.count) items (\(hidden) hidden)", depth: depth)
            }
        } else {
            ForEach(children) { child in
                if searchQuery.isEmpty || child.matches(searchQuery) {
                    NodeTreeView(node: child, depth: depth + 1,
                                 searchQuery: searchQuery,
                                 expandedArrayIDs: $expandedArrayIDs)
                }
            }
        }
    }

    private func expandToggleRow(label: String, depth: Int) -> some View {
        HStack(spacing: 6) {
            Spacer().frame(width: CGFloat(depth + 1) * 16)
            Button(label) {
                if showAllChildren {
                    expandedArrayIDs.remove(node.id)
                } else {
                    expandedArrayIDs.insert(node.id)
                }
            }
            .buttonStyle(.plain)
            .font(.caption.monospaced())
            .foregroundStyle(.teal)
            Spacer()
        }
        .padding(.vertical, 2)
    }
}
