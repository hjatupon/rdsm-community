import SwiftUI
import TFTree

/// Visual node-link diagram of the TF tree hierarchy, rendered via SwiftUI Canvas.
/// Shows frames as labeled nodes connected by lines in a top-down spatial layout.
public struct TFTreeDiagramView: View {
    public let edges: [TFEdgeInfo]
    public let rateInfos: [String: TFEdgeRateInfo]
    public let rateThreshold: Double
    public let staleAfter: Double
    public var selectedFrame: String?
    public var onFrameSelected: ((String) -> Void)?

    public init(edges: [TFEdgeInfo], rateInfos: [String: TFEdgeRateInfo],
                rateThreshold: Double, staleAfter: Double,
                selectedFrame: String? = nil,
                onFrameSelected: ((String) -> Void)? = nil) {
        self.edges = edges
        self.rateInfos = rateInfos
        self.rateThreshold = rateThreshold
        self.staleAfter = staleAfter
        self.selectedFrame = selectedFrame
        self.onFrameSelected = onFrameSelected
    }

    @State private var scrollOffset: CGPoint = .zero
    @State private var nodePositions: [String: CGPoint] = [:]
    @State private var contentSize: CGSize = .zero

    private let nodeWidth: CGFloat = 110
    private let nodeHeight: CGFloat = 28
    private let hSpacing: CGFloat = 20
    private let vSpacing: CGFloat = 40
    private let topPadding: CGFloat = 30

    public var body: some View {
        GeometryReader { geo in
            ScrollView([.horizontal, .vertical]) {
                Canvas { context, canvasSize in
                    // Compute layout
                    let layout = computeLayout()
                    nodePositions = layout.positions
                    contentSize = layout.contentSize

                    // Draw edges (lines from parent to child)
                    for edge in edges {
                        guard let parentPt = layout.positions[edge.parent],
                              let childPt = layout.positions[edge.child] else { continue }
                        let isChain = isEdgeInChain(edge)
                        let color: Color = isChain ? Color.accentColor : Color.secondary.opacity(0.35)
                        let lineWidth: CGFloat = isChain ? 2.0 : 1.0
                        var path = Path()
                        let midY = (parentPt.y + childPt.y) / 2
                        path.move(to: CGPoint(x: parentPt.x, y: parentPt.y + nodeHeight / 2))
                        path.addCurve(
                            to: CGPoint(x: childPt.x, y: childPt.y - nodeHeight / 2),
                            control1: CGPoint(x: parentPt.x, y: midY),
                            control2: CGPoint(x: childPt.x, y: midY))
                        context.stroke(path, with: .color(color), lineWidth: lineWidth)
                    }

                    // Draw nodes
                    for (name, pt) in layout.positions {
                        drawNode(context: context, name: name, at: pt)
                    }
                }
                .frame(width: max(geo.size.width, contentSize.width),
                       height: max(geo.size.height, contentSize.height))
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Layout computation (Reingold-Tilford simplified)

    private func computeLayout() -> (positions: [String: CGPoint], contentSize: CGSize) {
        let roots = findRoots()
        let tree = buildChildrenMap()
        var positions: [String: CGPoint] = [:]
        var nextX: CGFloat = 20

        func layoutSubtree(_ name: String, depth: Int) {
            let children = tree[name] ?? []
            let y = topPadding + CGFloat(depth) * (nodeHeight + vSpacing)

            if children.isEmpty {
                // Leaf node: assign position and advance x
                positions[name] = CGPoint(x: nextX + nodeWidth / 2, y: y)
                nextX += nodeWidth + hSpacing
            } else {
                // Internal node: layout children first, then center above them
                for child in children {
                    layoutSubtree(child, depth: depth + 1)
                }
                let childXs = children.compactMap { positions[$0]?.x }
                if let minX = childXs.min(), let maxX = childXs.max() {
                    positions[name] = CGPoint(x: (minX + maxX) / 2, y: y)
                } else {
                    positions[name] = CGPoint(x: nextX + nodeWidth / 2, y: y)
                    nextX += nodeWidth + hSpacing
                }
            }
        }

        for root in roots {
            layoutSubtree(root, depth: 0)
        }

        // Layout orphan frames (not connected to any root)
        let allChildren = Set(edges.map(\.child))
        let allParents = Set(edges.map(\.parent))
        let connected = allChildren.union(allParents)
        let orphans = Set(nodePositions.keys).subtracting(connected)
        // Actually orphans are frames that appear only as children of non-root nodes
        // For now, just layout any frame that wasn't positioned
        let maxY = positions.values.map(\.y).max() ?? 0
        let orphanStartY = maxY + nodeHeight + vSpacing * 2
        var orphanIdx = 0
        for name in edges.map(\.child).sorted() where positions[name] == nil {
            let x = 20 + CGFloat(orphanIdx) * (nodeWidth + hSpacing) + nodeWidth / 2
            positions[name] = CGPoint(x: x, y: orphanStartY)
            orphanIdx += 1
        }

        let maxX = (positions.values.map(\.x).max() ?? 0) + nodeWidth + 40
        let maxYTotal = (positions.values.map(\.y).max() ?? 0) + nodeHeight + 40
        return (positions, CGSize(width: maxX, height: maxYTotal))
    }

    private func findRoots() -> [String] {
        let children = Set(edges.map(\.child))
        let parents = Set(edges.map(\.parent))
        let roots = parents.subtracting(children)
        return roots.isEmpty ? Array(parents).sorted() : Array(roots).sorted()
    }

    private func buildChildrenMap() -> [String: [String]] {
        var map: [String: [String]] = [:]
        for edge in edges {
            map[edge.parent, default: []].append(edge.child)
        }
        // Sort children for stable layout
        for key in map.keys { map[key]?.sort() }
        return map
    }

    // MARK: - Drawing

    private func drawNode(context: GraphicsContext, name: String, at pt: CGPoint) {
        let rect = CGRect(
            x: pt.x - nodeWidth / 2,
            y: pt.y - nodeHeight / 2,
            width: nodeWidth,
            height: nodeHeight)
        let isSelected = name == selectedFrame
        let isChainMember = isFrameInChain(name)

        // Background
        let bgColor: Color
        if isSelected {
            bgColor = Color.accentColor.opacity(0.25)
        } else if isChainMember {
            bgColor = Color.accentColor.opacity(0.1)
        } else {
            bgColor = Color(nsColor: .controlBackgroundColor)
        }
        context.fill(Path(roundedRect: rect, cornerRadius: 5), with: .color(bgColor))

        // Border
        let borderColor: Color = isSelected ? Color.accentColor : Color.secondary.opacity(0.3)
        context.stroke(Path(roundedRect: rect, cornerRadius: 5), with: .color(borderColor), lineWidth: isSelected ? 1.5 : 0.5)

        // Label
        let text = Text(name).font(.system(size: 10, design: .monospaced))
        let resolved = context.resolve(text)
        let textSize = resolved.measure(in: CGSize(width: nodeWidth - 8, height: nodeHeight))
        let textRect = CGRect(
            x: pt.x - textSize.width / 2,
            y: pt.y - textSize.height / 2,
            width: textSize.width,
            height: textSize.height)
        context.draw(text, at: CGPoint(x: textRect.midX, y: textRect.midY))
    }

    // MARK: - Chain detection

    private var chainCache: Set<String> {
        guard let selected = selectedFrame else { return [] }
        // Build parent map for chain tracing
        var parentMap: [String: String] = [:]
        for edge in edges { parentMap[edge.child] = edge.parent }
        var chain = Set<String>([selected])
        var current = selected
        while let parent = parentMap[current] {
            chain.insert(parent)
            current = parent
        }
        return chain
    }

    private func isFrameInChain(_ name: String) -> Bool {
        guard selectedFrame != nil else { return false }
        return chainCache.contains(name)
    }

    private func isEdgeInChain(_ edge: TFEdgeInfo) -> Bool {
        guard selectedFrame != nil else { return false }
        return chainCache.contains(edge.parent) && chainCache.contains(edge.child)
    }
}
