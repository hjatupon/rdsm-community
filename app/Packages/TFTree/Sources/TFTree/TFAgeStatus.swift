import Foundation

// MARK: - TFAgeStatus

/// Staleness classification for a TF edge based on wall-clock receive time.
public enum TFAgeStatus: Sendable {
    case fresh
    case aging
    case stale

    public init(wallClockAgeSeconds: Double, greenThreshold: Double, yellowThreshold: Double) {
        if wallClockAgeSeconds < greenThreshold {
            self = .fresh
        } else if wallClockAgeSeconds < yellowThreshold {
            self = .aging
        } else {
            self = .stale
        }
    }

    public var color: (r: Double, g: Double, b: Double) {
        switch self {
        case .fresh:  return (0.24, 0.83, 0.50)
        case .aging:  return (0.96, 0.72, 0.25)
        case .stale:  return (0.95, 0.43, 0.43)
        }
    }

    public var label: String {
        switch self {
        case .fresh: return "fresh"
        case .aging: return "aging"
        case .stale: return "stale"
        }
    }
}
