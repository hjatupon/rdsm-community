#include <metal_stdlib>
using namespace metal;

struct OctomapVertex {
    packed_float3 position;
    uchar4 color;
};

struct OctomapUniforms {
    float4x4 mvp;
};

struct OctomapOut {
    float4 position [[position]];
    float4 color;
};

vertex OctomapOut octomapVertex(uint vid [[vertex_id]],
                                device const OctomapVertex *verts [[buffer(0)]],
                                constant OctomapUniforms &u [[buffer(1)]]) {
    OctomapVertex v = verts[vid];
    OctomapOut out;
    out.position = u.mvp * float4(v.position, 1.0);
    out.color = float4(v.color) / 255.0;
    return out;
}

fragment float4 octomapFragment(OctomapOut in [[stage_in]]) {
    return in.color;
}
