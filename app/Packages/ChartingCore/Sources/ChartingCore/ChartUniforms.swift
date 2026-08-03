import simd

/// Mirrors `struct ChartUniforms` in `Chart.metal` — field order and sizes must
/// match exactly. Any change here requires a matching change in the shader.
struct ChartUniforms {
    var tMin: Float       // left edge of the visible time window (seconds)
    var tMax: Float       // right edge
    var vMin: Float       // bottom of the value range
    var vMax: Float       // top of the value range
    var color: SIMD4<Float>  // RGBA series colour
    var lineWidth: Float  // half-width in NDC (unused by the vertex shader but
                          // kept for future geometry-shader use)
    var _pad0: Float = 0
    var _pad1: Float = 0
}
