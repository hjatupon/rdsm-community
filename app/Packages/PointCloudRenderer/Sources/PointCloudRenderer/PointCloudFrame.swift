import Foundation

/// One frame of a point cloud: parallel byte buffers describing `pointCount` points.
///
/// `positions` holds packed `float3` (x, y, z as 32-bit floats, 12 bytes/point — no
/// 16-byte SIMD padding). `intensities` and `colors` are optional parallel channels.
/// Buffers stay as raw `Data` so ingest is allocation-free; the renderer uploads them
/// to the GPU. Validate layout with ``hasValidLayout`` before trusting a frame.
///
/// `pointSize` and `colorMode` are per-layer render knobs baked in at ingest time
/// (from `LayerSettings`). The renderer uses them in place of global defaults.
public struct PointCloudFrame: Sendable {
    public let pointCount: Int
    /// Packed `float3` × `pointCount` (12 bytes per point).
    public let positions: Data
    /// `float` × `pointCount`, or `nil` when the cloud carries no intensity channel.
    public let intensities: Data?
    /// RGBA8 (4 bytes) **or** `float4` (16 bytes) × `pointCount`, or `nil`.
    public let colors: Data?
    /// Point sprite radius in Metal points. Sourced from `LayerSettings.pointSize`.
    public let pointSize: Float
    /// Per-layer color mode. Sourced from `LayerSettings` r/g/b/opacity.
    public let colorMode: PointColorMode

    public init(
        pointCount: Int,
        positions: Data,
        intensities: Data?,
        colors: Data?,
        pointSize: Float = 3.0,
        colorMode: PointColorMode = .axis(.z)
    ) {
        self.pointCount = pointCount
        self.positions = positions
        self.intensities = intensities
        self.colors = colors
        self.pointSize = pointSize
        self.colorMode = colorMode
    }
}

extension PointCloudFrame {
    /// Bytes one packed `float3` position occupies.
    static let positionStride = 12
    /// Bytes one `float` intensity occupies.
    static let intensityStride = 4
    /// Bytes one `float4` color occupies (the renderer's internal upload format).
    static let colorStride = 16

    var expectedPositionsByteCount: Int {
        pointCount * Self.positionStride
    }

    /// `true` only when `positions` holds exactly `pointCount` packed float3 values and
    /// any optional channel matches `pointCount`. ``PointCloudRenderer/update(frame:)``
    /// drops frames that fail this, so a malformed frame never reaches the GPU.
    var hasValidLayout: Bool {
        guard pointCount >= 0, positions.count == expectedPositionsByteCount else { return false }
        if let intensities, intensities.count != pointCount * Self.intensityStride { return false }
        if let colors {
            let rgba8 = pointCount * 4
            let float4 = pointCount * Self.colorStride
            if colors.count != rgba8, colors.count != float4 { return false }
        }
        return true
    }
}
