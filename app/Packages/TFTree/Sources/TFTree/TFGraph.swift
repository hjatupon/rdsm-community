import Foundation
import simd

// MARK: - Timestamped sample

/// A single transform sample with its capture timestamp (nanoseconds).
struct TFSample: Sendable {
    let timestamp: UInt64
    let receivedAtNs: UInt64
    let transform: TFTransform
}

// MARK: - Edge key

/// Identifies a directed TF edge (parent → child).
struct TFEdge: Hashable, Sendable {
    let parent: String
    let child: String
}

// MARK: - TFGraph

/// In-memory directed graph of transform edges with per-edge temporal history.
///
/// **Static edges** are stored separately and never expire.
/// **Dynamic edges** are stored as timestamp-sorted arrays; samples older than
/// `historyDuration` nanoseconds are pruned on each insert.
///
/// Not thread-safe — must be accessed through the `TFTree` actor.
struct TFGraph: Sendable {
    private var dynamic: [TFEdge: [TFSample]] = [:]  // sorted by timestamp
    private var statics: [TFEdge: TFTransform] = [:]
    private var staticTimestamps: [TFEdge: UInt64] = [:]  // insertion timestamp for static edges
    let historyDurationNs: UInt64

    init(historyDuration: TimeInterval) {
        self.historyDurationNs = UInt64(max(0, historyDuration) * 1_000_000_000)
    }

    // MARK: - Insert

    mutating func insert(
        parent: String,
        child: String,
        transform: TFTransform,
        at timestamp: UInt64,
        isStatic: Bool)
    {
        let edge = TFEdge(parent: parent, child: child)
        if isStatic {
            statics[edge] = transform
            staticTimestamps[edge] = timestamp
            return
        }

        let receivedAtNs = UInt64(Date().timeIntervalSince1970 * 1_000_000_000)
        let sample = TFSample(timestamp: timestamp, receivedAtNs: receivedAtNs, transform: transform)
        var samples = dynamic[edge] ?? []

        // Insert sorted by timestamp (most common case: append to end)
        if samples.last.map({ $0.timestamp <= timestamp }) ?? true {
            samples.append(sample)
        } else {
            let idx = samples.partitionIndex { $0.timestamp > timestamp }
            samples.insert(sample, at: idx)
        }

        // Prune old samples
        if historyDurationNs > 0, let newest = samples.last?.timestamp {
            let cutoff = newest > historyDurationNs ? newest - historyDurationNs : 0
            samples.removeAll { $0.timestamp < cutoff }
        }
        dynamic[edge] = samples
    }

    // MARK: - Query

    /// Returns all known frame names (both parents and children of any edge).
    var frames: Set<String> {
        var names = Set<String>()
        for edge in dynamic.keys { names.insert(edge.parent); names.insert(edge.child) }
        for edge in statics.keys { names.insert(edge.parent); names.insert(edge.child) }
        return names
    }

    /// Returns the transform on edge (parent→child) at `timestamp`, or nil.
    /// Tries static edges first, then interpolates dynamic samples.
    func transform(parent: String, child: String, at timestamp: UInt64) -> TFTransform? {
        let edge = TFEdge(parent: parent, child: child)
        if let s = statics[edge] { return s }
        guard let samples = dynamic[edge], !samples.isEmpty else { return nil }
        return interpolate(samples: samples, at: timestamp)
    }

    /// All known edges (both dynamic and static).
    func allEdges() -> [TFEdge] {
        var result: [TFEdge] = []
        result.append(contentsOf: dynamic.keys)
        for edge in statics.keys where !result.contains(edge) {
            result.append(edge)
        }
        return result
    }

    // MARK: - Metadata for UI

    struct EdgeRawMetadata: Sendable {
        let edge: TFEdge
        let latestTransform: TFTransform?
        let latestTimestampNs: UInt64?
        let latestReceivedAtNs: UInt64?
        let sampleCount: Int
        let oldestTimestampNs: UInt64?
        let isStatic: Bool
    }

    func edgeMetadata() -> [EdgeRawMetadata] {
        var result: [EdgeRawMetadata] = []

        for (edge, samples) in dynamic {
            result.append(EdgeRawMetadata(
                edge: edge,
                latestTransform: samples.last?.transform,
                latestTimestampNs: samples.last?.timestamp,
                latestReceivedAtNs: samples.last?.receivedAtNs,
                sampleCount: samples.count,
                oldestTimestampNs: samples.first?.timestamp,
                isStatic: false))
        }
        for (edge, transform) in statics {
            if !result.contains(where: { $0.edge == edge }) {
                result.append(EdgeRawMetadata(
                    edge: edge,
                    latestTransform: transform,
                    latestTimestampNs: staticTimestamps[edge],
                    latestReceivedAtNs: staticTimestamps[edge],
                    sampleCount: 1,
                    oldestTimestampNs: staticTimestamps[edge],
                    isStatic: true))
            }
        }
        return result
    }

    // MARK: - Rate computation (sliding window)

    /// Compute Hz from the most recent `windowSeconds` of samples.
    func slidingWindowHz(edge: TFEdge, windowSeconds: Double) -> Double {
        guard let samples = dynamic[edge], samples.count >= 2 else { return 0.0 }
        let windowNs = UInt64(windowSeconds * 1_000_000_000)
        guard let newest = samples.last?.timestamp else { return 0.0 }
        let cutoff = newest > windowNs ? newest - windowNs : 0
        let inWindow = samples.filter { $0.timestamp >= cutoff }
        guard inWindow.count >= 2,
              let oldest = inWindow.first?.timestamp,
              let latest = inWindow.last?.timestamp,
              latest > oldest else { return 0.0 }
        let spanSec = Double(latest - oldest) / 1_000_000_000.0
        return spanSec > 0 ? Double(inWindow.count - 1) / spanSec : 0.0
    }

    /// Time in seconds since the last sample on this edge.
    func ageSeconds(edge: TFEdge, nowNs: UInt64) -> Double {
        if let samples = dynamic[edge], let newest = samples.last?.timestamp {
            return nowNs > newest ? Double(nowNs - newest) / 1_000_000_000.0 : 0
        }
        if let ts = staticTimestamps[edge] {
            return nowNs > ts ? Double(nowNs - ts) / 1_000_000_000.0 : 0
        }
        return Double.greatestFiniteMagnitude
    }

    /// Number of samples in the sliding window for an edge.
    func sampleCountInWindow(edge: TFEdge, windowSeconds: Double) -> Int {
        guard let samples = dynamic[edge] else { return 0 }
        let windowNs = UInt64(windowSeconds * 1_000_000_000)
        guard let newest = samples.last?.timestamp else { return 0 }
        let cutoff = newest > windowNs ? newest - windowNs : 0
        return samples.filter { $0.timestamp >= cutoff }.count
    }

    /// Adjacency list: for BFS. Returns all neighbors of `frame` and whether the edge
    /// is forward (true) or inverse (false).
    func neighbors(of frame: String) -> [(neighbor: String, forward: Bool, edge: TFEdge)] {
        var result: [(String, Bool, TFEdge)] = []
        for edge in dynamic.keys {
            if edge.parent == frame { result.append((edge.child, true, edge)) }
            if edge.child == frame { result.append((edge.parent, false, edge)) }
        }
        for edge in statics.keys {
            if edge.parent == frame { result.append((edge.child, true, edge)) }
            if edge.child == frame { result.append((edge.parent, false, edge)) }
        }
        return result
    }

    // MARK: - Interpolation

    private func interpolate(samples: [TFSample], at t: UInt64) -> TFTransform? {
        guard !samples.isEmpty else { return nil }

        // Exact match
        if let exact = samples.first(where: { $0.timestamp == t }) { return exact.transform }

        let first = samples[0], last = samples[samples.count - 1]

        // Before first sample — no data yet
        if t < first.timestamp { return nil }

        // After last sample — extrapolate with last known (assume robot hasn't moved)
        if t > last.timestamp { return last.transform }

        // Binary search for bracketing pair
        let idx = samples.partitionIndex { $0.timestamp > t }
        guard idx > 0 && idx < samples.count else { return nil }

        let lo = samples[idx - 1]
        let hi = samples[idx]

        let span = hi.timestamp - lo.timestamp
        guard span > 0 else { return lo.transform }
        let alpha = Double(t - lo.timestamp) / Double(span)

        return TFTransform(
            translation: lo.transform.translation + alpha * (hi.transform.translation - lo.transform.translation),
            rotation: simd_slerp(lo.transform.rotation, hi.transform.rotation, alpha))
    }
}

// MARK: - Array partition helper

private extension Array {
    /// Returns the first index where `predicate` is true (stable partition point).
    func partitionIndex(where predicate: (Element) -> Bool) -> Int {
        var lo = 0, hi = count
        while lo < hi {
            let mid = lo + (hi - lo) / 2
            if predicate(self[mid]) { hi = mid } else { lo = mid + 1 }
        }
        return lo
    }
}
