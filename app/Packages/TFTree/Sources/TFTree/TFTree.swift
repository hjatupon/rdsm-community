import Foundation
import Logging
import simd

// MARK: - TFEdgeInfo

/// Transform metadata for a single TF edge, used by the TF Tree UI panel.
public struct TFEdgeInfo: Sendable {
    public let parent: String
    public let child: String
    public let translation: (x: Double, y: Double, z: Double)
    public let rotation: (roll: Double, pitch: Double, yaw: Double)  // degrees
    public let isStatic: Bool
    public let lastUpdateNs: UInt64   // nanoseconds since epoch
    public let hz: Double             // estimated publish rate (0 for static)
    public let receivedAtNs: UInt64   // wall-clock receive time
    public let latencyNs: UInt64      // receivedAtNs - lastUpdateNs (if positive)

    public init(parent: String, child: String,
                translation: (x: Double, y: Double, z: Double),
                rotation: (roll: Double, pitch: Double, yaw: Double),
                isStatic: Bool, lastUpdateNs: UInt64, hz: Double,
                receivedAtNs: UInt64 = 0, latencyNs: UInt64 = 0) {
        self.parent = parent
        self.child = child
        self.translation = translation
        self.rotation = rotation
        self.isStatic = isStatic
        self.lastUpdateNs = lastUpdateNs
        self.hz = hz
        self.receivedAtNs = receivedAtNs
        self.latencyNs = latencyNs
    }
}

// MARK: - TFEdgeRateInfo

/// Per-edge publish rate info for Hz badges and staleness detection.
public struct TFEdgeRateInfo: Sendable {
    public let parent: String
    public let child: String
    public let hz: Double
    public let sampleCount: Int
    public let ageSeconds: Double
    public let isStatic: Bool
    public let lastUpdateNs: UInt64
}

/// A TF2-compatible transform tree with temporal history and BFS path-finding.
///
/// ## Contract C4
/// ``lookup(from:to:at:)`` **never throws** — it returns `nil` when the path is
/// disconnected, when the timestamp is out of the history window, or when any
/// edge sample is absent. Callers must handle `nil` gracefully.
///
/// ## Precision
/// All arithmetic uses `Double` to match tf2 reference accuracy (≤1e-6 m / ≤1e-7 rad).
///
/// ## Thread safety
/// `TFTree` is a Swift actor. `insert` and `lookup` are actor-isolated and safe
/// from concurrent callers.
public actor TFTree {

    private var graph: TFGraph
    private let logger: any LoggerProtocol

    // Path cache: (source, target) → [edges]. Invalidated when graph topology changes.
    private var pathCache: [PathKey: [PathStep]] = [:]

    public init(historyDuration: TimeInterval = 10.0, logger: any LoggerProtocol = NullLogger()) {
        self.graph = TFGraph(historyDuration: historyDuration)
        self.logger = logger
    }

    // MARK: - Topology query

    /// All (parent, child) edges in the tree, including static ones.
    public func edges() -> [(parent: String, child: String)] {
        graph.allEdges().map { ($0.parent, $0.child) }
    }

    /// All edges with full transform metadata for display in the TF Tree panel.
    public func edgesWithMetadata() -> [TFEdgeInfo] {
        let now = UInt64(Date().timeIntervalSince1970 * 1_000_000_000)
        return graph.edgeMetadata().map { meta in
            let t = meta.latestTransform ?? .identity
            let (roll, pitch, yaw) = quaternionToRPYDegrees(t.rotation)
            let hz: Double
            if meta.isStatic || meta.sampleCount < 2 {
                hz = 0.0
            } else {
                hz = graph.slidingWindowHz(edge: meta.edge, windowSeconds: 2.0)
            }
            let receivedAt = meta.latestReceivedAtNs ?? now
            let latencyNs = receivedAt > (meta.latestTimestampNs ?? 0)
                ? receivedAt - (meta.latestTimestampNs ?? 0)
                : 0
            return TFEdgeInfo(
                parent: meta.edge.parent,
                child: meta.edge.child,
                translation: (x: t.translation.x, y: t.translation.y, z: t.translation.z),
                rotation: (roll: roll, pitch: pitch, yaw: yaw),
                isStatic: meta.isStatic,
                lastUpdateNs: meta.latestTimestampNs ?? now,
                hz: hz,
                receivedAtNs: receivedAt,
                latencyNs: latencyNs)
        }
    }

    // MARK: - Per-frame rate info

    /// Returns per-edge rate info using a sliding time window.
    public func frameRates(windowSeconds: Double = 2.0) -> [TFEdgeRateInfo] {
        let nowNs = UInt64(Date().timeIntervalSince1970 * 1_000_000_000)
        return graph.edgeMetadata().map { meta in
            let age: Double
            if meta.isStatic {
                age = 0
            } else if let newest = meta.latestTimestampNs {
                age = nowNs > newest ? Double(nowNs - newest) / 1_000_000_000.0 : 0
            } else {
                age = Double.greatestFiniteMagnitude
            }
            let hz: Double
            if meta.isStatic {
                hz = 0
            } else {
                hz = graph.slidingWindowHz(edge: meta.edge, windowSeconds: windowSeconds)
            }
            let count: Int
            if meta.isStatic {
                count = meta.sampleCount
            } else {
                count = graph.sampleCountInWindow(edge: meta.edge, windowSeconds: windowSeconds)
            }
            return TFEdgeRateInfo(
                parent: meta.edge.parent,
                child: meta.edge.child,
                hz: hz,
                sampleCount: count,
                ageSeconds: age,
                isStatic: meta.isStatic,
                lastUpdateNs: meta.latestTimestampNs ?? nowNs)
        }
    }

    // MARK: - RPY conversion

    private func quaternionToRPYDegrees(_ q: simd_quatd) -> (roll: Double, pitch: Double, yaw: Double) {
        let x = q.imag.x, y = q.imag.y, z = q.imag.z, w = q.real
        let sinrCosp = 2.0 * (w * x + y * z)
        let cosrCosp = 1.0 - 2.0 * (x * x + y * y)
        let roll = atan2(sinrCosp, cosrCosp)
        let sinp = 2.0 * (w * y - z * x)
        let pitch = abs(sinp) >= 1.0 ? copysign(.pi / 2.0, sinp) : asin(sinp)
        let sinyCosp = 2.0 * (w * z + x * y)
        let cosyCosp = 1.0 - 2.0 * (y * y + z * z)
        let yaw = atan2(sinyCosp, cosyCosp)
        let toDeg = 180.0 / .pi
        return (roll * toDeg, pitch * toDeg, yaw * toDeg)
    }

    // MARK: - Insert

    // MARK: - Frame ID normalization

    /// Strips a leading "/" from frame IDs so "/base_link" and "base_link" are treated
    /// as the same frame (rosbridge sometimes includes the leading slash).
    private func normalize(_ frameID: String) -> String {
        frameID.hasPrefix("/") ? String(frameID.dropFirst()) : frameID
    }

    /// Records a transform from `parent` to `child` at `timestamp` (nanoseconds).
    ///
    /// Static transforms (`isStatic: true`) persist indefinitely and are never
    /// overwritten by dynamic samples for the same edge.
    public func insert(
        parent: String,
        child: String,
        transform: TFTransform,
        at timestamp: UInt64,
        isStatic: Bool = false)
    {
        let p = normalize(parent)
        let c = normalize(child)
        let topologyChanged = !graph.frames.contains(c) || !graph.frames.contains(p)
        graph.insert(parent: p, child: c, transform: transform, at: timestamp, isStatic: isStatic)
        if topologyChanged { pathCache.removeAll() }
        logger.debug("TFTree: inserted \(p)→\(c) t=\(timestamp) static=\(isStatic)", fields: [])
    }

    // MARK: - Lookup

    /// Returns the transform from `source` to `target` at `timestamp`, or `nil`.
    ///
    /// Performs BFS through the graph using both forward and inverse edges.
    /// Interpolates (SLERP + linear) between the two bracketing samples for
    /// each edge in the path.
    public func lookup(from source: String, to target: String, at timestamp: UInt64) -> TFTransform? {
        let source = normalize(source)
        let target = normalize(target)
        guard source != target else { return .identity }

        let key = PathKey(source: source, target: target)
        let steps: [PathStep]
        if let cached = pathCache[key] {
            steps = cached
        } else if let found = bfs(from: source, to: target) {
            if pathCache.count >= 512 { pathCache.removeAll() }
            pathCache[key] = found
            steps = found
        } else {
            logger.debug("TFTree: no path \(source)→\(target)", fields: [])
            return nil
        }

        // Compose transforms along the path
        var result = TFTransform.identity
        for step in steps {
            guard let t = graph.transform(parent: step.edge.parent, child: step.edge.child, at: timestamp) else {
                logger.debug("TFTree: missing sample on \(step.edge.parent)→\(step.edge.child) at t=\(timestamp)", fields: [])
                return nil
            }
            let contrib = step.forward ? t.inverse : t
            result = result.then(contrib)
        }
        return result
    }

    /// Returns all known frame names in the tree.
    public func frames() -> [String] {
        Array(graph.frames).sorted()
    }

    // MARK: - BFS

    private func bfs(from source: String, to target: String) -> [PathStep]? {
        var visited = Set<String>([source])
        var queue: [(frame: String, path: [PathStep])] = [(source, [])]

        while !queue.isEmpty {
            let (current, path) = queue.removeFirst()
            for (neighbor, forward, edge) in graph.neighbors(of: current) {
                guard !visited.contains(neighbor) else { continue }
                let step = PathStep(edge: edge, forward: forward)
                let newPath = path + [step]
                if neighbor == target { return newPath }
                visited.insert(neighbor)
                queue.append((neighbor, newPath))
            }
        }
        return nil
    }

    /// Returns the set of frame names in the chain from any root to the given frame.
    /// Uses BFS from the target frame outward, collecting all ancestors.
    public func chain(from frame: String) -> Set<String> {
        var chain = Set<String>([frame])
        var visited = Set<String>([frame])
        var queue = [frame]
        while !queue.isEmpty {
            let current = queue.removeFirst()
            // Walk backward: find edges where current is the child → parent
            for edge in graph.allEdges() {
                if edge.child == current && !visited.contains(edge.parent) {
                    chain.insert(edge.parent)
                    visited.insert(edge.parent)
                    queue.append(edge.parent)
                }
            }
        }
        return chain
    }
}

// MARK: - Path helpers

private struct PathKey: Hashable {
    let source: String
    let target: String
}

private struct PathStep: Sendable {
    let edge: TFEdge
    let forward: Bool  // true = parent→child, false = child→parent (inverse)
}

// MARK: - NullLogger

public struct NullLogger: LoggerProtocol, Sendable {
    public init() {}
    public func debug(_ message: String, fields: [LogField]) {}
    public func info(_ message: String, fields: [LogField]) {}
    public func warning(_ message: String, fields: [LogField]) {}
    public func error(_ message: String, fields: [LogField]) {}
}
