import Foundation

/// A serialisable rectangle used for panel and window frames.
///
/// Replaces `CGRect` in serialised state — `CGRect` doesn't conform to `Codable`
/// in the SPM CLI context. UI modules convert to `CGRect` at the boundary.
public struct LayoutRect: Codable, Sendable, Hashable, Equatable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public static let zero = LayoutRect(x: 0, y: 0, width: 0, height: 0)

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
}
