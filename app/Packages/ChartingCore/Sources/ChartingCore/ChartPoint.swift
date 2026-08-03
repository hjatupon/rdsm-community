import Foundation

/// A single (time, value) sample on a chart series.
public struct ChartPoint: Sendable {
    public let t: Double      // seconds (monotonic)
    public let value: Double

    public init(t: Double, value: Double) {
        self.t = t
        self.value = value
    }
}
