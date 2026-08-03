import Foundation
import Transport

/// Pure filter logic for the topic browser — no SwiftUI dependency.
///
/// Tests cover this struct directly; the view simply calls `apply(to:)`.
public struct TopicFilter: Sendable, Equatable {

    public enum Mode: String, CaseIterable, Sendable {
        case all      = "All"
        case sensor   = "Sensors"
        case geometry = "Geometry"
        case logging  = "Logs"
    }

    public var searchText: String = ""
    public var mode: Mode = .all

    public init(searchText: String = "", mode: Mode = .all) {
        self.searchText = searchText
        self.mode = mode
    }

    /// Returns only the topics that match both the search text and the type mode.
    public func apply(to topics: [TopicDescriptor]) -> [TopicDescriptor] {
        topics.filter { matches($0) }
    }

    // MARK: - Private

    private func matches(_ topic: TopicDescriptor) -> Bool {
        matchesSearch(topic) && matchesMode(topic)
    }

    private func matchesSearch(_ topic: TopicDescriptor) -> Bool {
        guard !searchText.isEmpty else { return true }
        let q = searchText.lowercased()
        return topic.name.lowercased().contains(q)
            || topic.schemaName.lowercased().contains(q)
    }

    private func matchesMode(_ topic: TopicDescriptor) -> Bool {
        switch mode {
        case .all: return true
        case .sensor:
            let s = topic.schemaName.lowercased()
            return s.contains("image") || s.contains("pointcloud") || s.contains("laserscan")
                || s.contains("range") || s.contains("imu") || s.contains("magneticfield")
                || s.contains("battery") || s.contains("navsatfix") || s.contains("joy")
        case .geometry:
            let s = topic.schemaName.lowercased()
            return s.contains("pose") || s.contains("transform") || s.contains("odometry")
                || s.contains("twist") || s.contains("accel") || s.contains("path")
                || s.contains("polygon") || s.contains("marker") || s.contains("jointstate")
                || s.contains("wrench")
        case .logging:
            let s = topic.schemaName.lowercased()
            return s.contains("log") || s.contains("string") || s.contains("header")
                || s.contains("clock") || s.contains("time")
        }
    }
}
