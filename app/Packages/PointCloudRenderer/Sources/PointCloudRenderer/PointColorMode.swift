import simd

/// A spatial axis, used by ``PointColorMode/axis(_:)`` to color points by coordinate.
public enum Axis: Sendable { case x, y, z }

/// How a point cloud is colored. The mapping is computed in-shader; the CPU-side
/// reference math lives in ``PointColoring`` so it can be unit-tested without a GPU.
public enum PointColorMode: Sendable {
    /// Ramp by the point's coordinate along `axis`, normalized to the cloud's bounds.
    case axis(Axis)
    /// Ramp by the intensity channel, normalized and clamped to `[min, max]`.
    case intensity(min: Float, max: Float)
    /// Use the per-point RGBA color channel verbatim.
    case rgb
    /// A single flat color for every point.
    case constant(SIMD4<Float>)
}

extension PointColorMode {
    /// Shader selector: 0 axis, 1 intensity, 2 rgb, 3 constant.
    var modeIndex: Int32 {
        switch self {
        case .axis: 0
        case .intensity: 1
        case .rgb: 2
        case .constant: 3
        }
    }

    /// Axis selector (0 = x, 1 = y, 2 = z); 0 for non-axis modes.
    var axisIndex: Int32 {
        guard case let .axis(axis) = self else { return 0 }
        switch axis {
        case .x: return 0
        case .y: return 1
        case .z: return 2
        }
    }

    /// The flat color for ``constant(_:)``; opaque white otherwise.
    var constantColor: SIMD4<Float> {
        guard case let .constant(color) = self else { return SIMD4(1, 1, 1, 1) }
        return color
    }

    /// The clamp window for ``intensity(min:max:)``; `0...1` otherwise.
    var intensityRange: (min: Float, max: Float) {
        guard case let .intensity(lo, hi) = self else { return (0, 1) }
        return (lo, hi)
    }

    /// Whether this mode reads the frame's color channel (``rgb``).
    var needsColors: Bool {
        if case .rgb = self { true } else { false }
    }

    /// Whether this mode reads the frame's intensity channel.
    var needsIntensities: Bool {
        if case .intensity = self { true } else { false }
    }
}

/// CPU mirror of the shader's color math, exposed so the mapping is unit-testable
/// without a GPU. The Metal vertex shader replicates these two functions exactly.
public enum PointColoring {
    /// Blue → red ramp over a normalized `t`, clamped to `[0, 1]`. Endpoints are
    /// distinct so the two ends of an axis/intensity range read differently.
    public static func ramp(_ t: Float) -> SIMD4<Float> {
        let c = max(0, min(1, t))
        return SIMD4(c, 0.15 + 0.5 * (1 - abs(2 * c - 1)), 1 - c, 1)
    }

    /// Normalizes `value` into `[0, 1]` across `[lo, hi]`, clamping out-of-range
    /// inputs. A degenerate range (`hi <= lo`) maps everything to 0.
    public static func normalize(_ value: Float, min lo: Float, max hi: Float) -> Float {
        guard hi > lo else { return 0 }
        return max(0, min(1, (value - lo) / (hi - lo)))
    }
}
