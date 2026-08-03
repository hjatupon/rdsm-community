#include <metal_stdlib>
using namespace metal;

// Mirrors Swift `struct GridUniforms`.
struct GridUniforms {
    float4x4 mvp;
    float4 color;
};

struct GridVertexOut {
    float4 position [[position]];
    float4 color;
};

vertex GridVertexOut gridVertex(uint vid [[vertex_id]],
                                device const packed_float3 *positions [[buffer(0)]],
                                constant GridUniforms &u [[buffer(1)]]) {
    GridVertexOut out;
    out.position = u.mvp * float4(float3(positions[vid]), 1.0);
    out.color = u.color;
    return out;
}

fragment float4 gridFragment(GridVertexOut in [[stage_in]]) {
    return in.color;
}
