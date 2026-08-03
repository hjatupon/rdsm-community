import Foundation

// MARK: - VizCategory

public enum VizCategory: String, CaseIterable, Sendable, Identifiable {
    case all      = "All"
    case charts   = "Charts"
    case gauges   = "Gauges"
    case spatial  = "Spatial"
    case robot    = "Robot"
    case data     = "Data"
    case media    = "Media"

    public var id: String { rawValue }

    public var sfSymbol: String {
        switch self {
        case .all:     return "square.grid.2x2"
        case .charts:  return "chart.line.uptrend.xyaxis"
        case .gauges:  return "gauge.medium"
        case .spatial: return "map"
        case .robot:   return "figure.walk"
        case .data:    return "list.bullet"
        case .media:   return "photo"
        }
    }
}

// MARK: - VisualizationDescriptor

/// A single entry in the visualization catalog.
/// Pure data — no SwiftUI dependency. Rendering is done by ``VisualizationRegistry/makeView(id:snapshot:)``.
public struct VisualizationDescriptor: Identifiable, Sendable {

    public let id: String           // e.g. "laser.polar", "generic.histogram"
    public let name: String
    public let tagline: String      // one-line description shown in the picker card
    public let category: VizCategory
    public let sfSymbol: String     // SF Symbols name for the card icon

    // MARK: Compatibility

    /// Exact schema names this viz is designed for. Empty = compatible with everything.
    public let compatibleSchemas: Set<String>
    /// Schema name substrings that trigger compatibility (case-insensitive).
    public let compatibleKeywords: [String]
    /// 0–100; higher = shown first in the "Recommended" section.
    public let recommendationScore: Int

    public init(id: String,
                name: String,
                tagline: String,
                category: VizCategory,
                sfSymbol: String,
                compatibleSchemas: Set<String>,
                compatibleKeywords: [String],
                recommendationScore: Int) {
        self.id = id
        self.name = name
        self.tagline = tagline
        self.category = category
        self.sfSymbol = sfSymbol
        self.compatibleSchemas = compatibleSchemas
        self.compatibleKeywords = compatibleKeywords
        self.recommendationScore = recommendationScore
    }

    // MARK: Query helpers

    public func isCompatible(with schema: String) -> Bool {
        if compatibleSchemas.isEmpty && compatibleKeywords.isEmpty { return true }
        let lower = schema.lowercased()
        if compatibleSchemas.contains(lower) { return true }
        return compatibleKeywords.contains(where: { lower.contains($0) })
    }

    public func score(for schema: String) -> Int {
        guard isCompatible(with: schema) else { return 0 }
        let lower = schema.lowercased()
        if compatibleSchemas.contains(lower) { return recommendationScore }
        if compatibleKeywords.contains(where: { lower.contains($0) }) {
            return max(recommendationScore - 10, 1)
        }
        return max(recommendationScore - 20, 1)
    }
}
