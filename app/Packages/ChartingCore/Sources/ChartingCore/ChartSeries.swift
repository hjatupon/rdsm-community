import simd

/// A named, coloured data series backed by a lock-free ring buffer.
///
/// The caller owns the `RingBuffer` and pushes samples from the producer thread;
/// `ChartView` reads from the same buffer on the render thread.  Both sides must
/// honour the SPSC contract — see `RingBuffer`.
public struct ChartSeries: Sendable {
    public let id: String
    public let color: SIMD4<Float>  // RGBA, [0,1]
    public let buffer: RingBuffer<ChartPoint>

    public init(id: String, color: SIMD4<Float>, capacity: Int = 4096) {
        self.id = id
        self.color = color
        self.buffer = RingBuffer<ChartPoint>(capacity: capacity)
    }
}
