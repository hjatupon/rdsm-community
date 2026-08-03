import Foundation

/// Persists per-topic visualization overrides to UserDefaults.
///
/// Key pattern: `"inspector.vizOverride.<topicName>"`
/// Value: VisualizationDescriptor.id string, or nil = auto (default).
@MainActor
public final class VizOverrideStore {

    public static let shared = VizOverrideStore()
    private init() {}

    private let defaults = UserDefaults.standard
    private func key(for topic: String) -> String { "inspector.vizOverride.\(topic)" }

    /// Returns the stored override descriptor ID for a topic, or nil if using auto-detection.
    public func override(for topic: String) -> String? {
        defaults.string(forKey: key(for: topic))
    }

    /// Stores a visualization override for a topic.
    public func set(vizID: String, for topic: String) {
        defaults.set(vizID, forKey: key(for: topic))
    }

    /// Removes the override — inspector returns to auto-detected visualization.
    public func reset(for topic: String) {
        defaults.removeObject(forKey: key(for: topic))
    }
}
