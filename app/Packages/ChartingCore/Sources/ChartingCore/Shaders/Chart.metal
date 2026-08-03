#include <metal_stdlib>
using namespace metal;

// Mirrors Swift `struct ChartUniforms` — field order and offsets must match.
struct ChartUniforms {
    float tMin;
    float tMax;
    float vMin;
    float vMax;
    float4 color;
    float lineWidth;
    float pad0;
    float pad1;
};

// Each vertex is a (t, value) sample packed as float2.
struct VertexIn {
    float2 sample [[attribute(0)]]; // x = t (seconds), y = value
};

struct VertexOut {
    float4 position [[position]];
    float4 color;
};

vertex VertexOut chartVertex(
    VertexIn in [[stage_in]],
    constant ChartUniforms &u [[buffer(1)]]
) {
    float tRange = u.tMax - u.tMin;
    float vRange = u.vMax - u.vMin;

    // Map t ∈ [tMin, tMax] → NDC x ∈ [-1, 1]
    float nx = (tRange > 0.0) ? ((in.sample.x - u.tMin) / tRange) * 2.0 - 1.0 : 0.0;
    // Map value ∈ [vMin, vMax] → NDC y ∈ [-1, 1]
    float ny = (vRange > 0.0) ? ((in.sample.y - u.vMin) / vRange) * 2.0 - 1.0 : 0.0;

    VertexOut out;
    out.position = float4(nx, ny, 0.0, 1.0);
    out.color = u.color;
    return out;
}

fragment float4 chartFragment(VertexOut in [[stage_in]]) {
    return in.color;
}
