#include <metal_stdlib>
using namespace metal;

// A minimal passthrough pipeline: a full-screen triangle whose color is the
// clear/tint constant. Exists so MetalCore ships a compilable .metal resource
// and the demo can prove the render loop binds a pipeline end to end.

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

// Single-triangle full-screen trick: 3 vertices cover the viewport, no buffer.
vertex VertexOut passthrough_vertex(uint vid [[vertex_id]]) {
    float2 positions[3] = { float2(-1.0, -3.0), float2(-1.0, 1.0), float2(3.0, 1.0) };
    VertexOut out;
    out.position = float4(positions[vid], 0.0, 1.0);
    out.uv = positions[vid] * 0.5 + 0.5;
    return out;
}

fragment float4 passthrough_fragment(VertexOut in [[stage_in]],
                                     constant float4 &tint [[buffer(0)]]) {
    return tint;
}
