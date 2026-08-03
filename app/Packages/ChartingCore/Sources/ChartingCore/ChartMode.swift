/// Rendering mode for a `ChartView`.
public enum ChartMode: Sendable {
    /// Always use the Metal line-strip renderer (fast path, ≥ 60 Hz).
    case metal
    /// Always use Apple's SwiftCharts (lower overhead at ≤ 60 Hz).
    case swiftCharts
    /// Automatically switch based on aggregate sample rate across all series.
    /// Switches to `.metal` when rate ≥ 60 Hz for two consecutive 1-second
    /// windows; falls back to `.swiftCharts` when rate < 30 Hz for five windows.
    case auto
}
