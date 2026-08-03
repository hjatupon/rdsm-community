#include <metal_stdlib>
using namespace metal;

// Mirrors Swift `struct PointUniforms` — field order and offsets must match exactly.
struct PointUniforms {
    float4x4 mvp;
    float4 constantColor;
    float axisMin;
    float axisMax;
    float intensityMin;
    float intensityMax;
    int colorMode;   // 0 axis, 1 intensity, 2 rgb, 3 constant
    int axisIndex;   // 0 x, 1 y, 2 z
    float pointSize;
};

// CPU mirror lives in `PointColoring.ramp` — keep the two in lockstep.
static float4 ramp(float t) {
    float c = clamp(t, 0.0, 1.0);
    return float4(c, 0.15 + 0.5 * (1.0 - abs(2.0 * c - 1.0)), 1.0 - c, 1.0);
}

struct VertexOut {
    float4 position [[position]];
    float pointSize [[point_size]];
    float4 color;
};

vertex VertexOut pointVertex(uint vid [[vertex_id]],
                             device const packed_float3 *positions [[buffer(0)]],
                             constant PointUniforms &u [[buffer(1)]],
                             device const float *intensities [[buffer(2)]],
                             device const float4 *colors [[buffer(3)]]) {
    float3 p = float3(positions[vid]);
    VertexOut out;
    out.position = u.mvp * float4(p, 1.0);
    out.pointSize = u.pointSize;

    float4 color;
    switch (u.colorMode) {
        case 0: { // axis
            float v = (u.axisIndex == 0) ? p.x : (u.axisIndex == 1 ? p.y : p.z);
            float t = (u.axisMax > u.axisMin) ? (v - u.axisMin) / (u.axisMax - u.axisMin) : 0.0;
            color = ramp(t);
            break;
        }
        case 1: { // intensity
            float iv = intensities[vid];
            float t = (u.intensityMax > u.intensityMin)
                ? (iv - u.intensityMin) / (u.intensityMax - u.intensityMin) : 0.0;
            color = ramp(t);
            break;
        }
        case 2: // rgb
            color = colors[vid];
            break;
        default: // constant
            color = u.constantColor;
            break;
    }
    out.color = color;
    return out;
}

fragment float4 pointFragment(VertexOut in [[stage_in]], float2 pc [[point_coord]]) {
    // Round sprite: discard fragments outside the inscribed circle.
    float2 d = pc - float2(0.5);
    if (dot(d, d) > 0.25) {
        discard_fragment();
    }
    return in.color;
}
