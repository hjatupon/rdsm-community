import Foundation
import simd

// MARK: - TFTree convenience methods for TF Universe

extension TFTree {

    /// Returns the depth of each frame from the root(s).
    public func computeDepths(roots: [String], childrenMap: [String: [String]]) -> [String: Int] {
        var depths: [String: Int] = [:]
        func dfs(_ name: String, depth: Int) {
            depths[name] = depth
            for child in childrenMap[name] ?? [] {
                dfs(child, depth: depth + 1)
            }
        }
        for root in roots { dfs(root, depth: 0) }
        return depths
    }

    /// Returns the number of hops from the given frame to its nearest root.
    public func distanceToRoot(frame: String, parentMap: [String: String]) -> Int {
        var dist = 0
        var cur = frame
        while let parent = parentMap[cur] {
            cur = parent
            dist += 1
        }
        return dist
    }

    /// Returns all ancestor frames of `frame`, from nearest to farthest.
    public func ancestors(frame: String, parentMap: [String: String]) -> [String] {
        var result: [String] = []
        var cur = frame
        while let parent = parentMap[cur] {
            result.append(parent)
            cur = parent
        }
        return result
    }

    /// Returns all descendant frames of `frame` (BFS).
    public func descendants(frame: String, childrenMap: [String: [String]]) -> [String] {
        var result: [String] = []
        var queue = [frame]
        while !queue.isEmpty {
            let cur = queue.removeFirst()
            for child in childrenMap[cur] ?? [] {
                result.append(child)
                queue.append(child)
            }
        }
        return result
    }

    /// Returns the longest chain of consecutive dynamic frames from any root.
    public func maxChainLength(edges: [(parent: String, child: String)],
                                isStatic: (String) -> Bool) -> Int {
        var childrenMap: [String: [String]] = [:]
        var parentMap: [String: String] = [:]
        for edge in edges {
            childrenMap[edge.parent, default: []].append(edge.child)
            parentMap[edge.child] = edge.parent
        }
        let roots = Set(parentMap.values).subtracting(parentMap.keys)

        func longest(_ name: String) -> Int {
            var maxChild = 0
            for child in childrenMap[name] ?? [] {
                if isStatic(child) { continue }
                maxChild = max(maxChild, longest(child))
            }
            return 1 + maxChild
        }

        return roots.map { longest($0) }.max() ?? 0
    }

    /// Builds a parent map (child → parent) from an edge list.
    public static func buildParentMap(edges: [(parent: String, child: String)]) -> [String: String] {
        var map: [String: String] = [:]
        for edge in edges { map[edge.child] = edge.parent }
        return map
    }
}
