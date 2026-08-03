#include <metal_stdlib>
using namespace metal;

struct OccupancyGridVertex {
    packed_float3 position;
    uchar4 color;
};

struct OccupancyGridUniforms {
    float4x4 mvp;
};

struct OccupancyGridOut {
    float4 position [[position]];
    float4 color;
};

vertex OccupancyGridOut occupancyGridVertex(uint vid [[vertex_id]],
                                            device const OccupancyGridVertex *verts [[buffer(0)]],
                                            constant OccupancyGridUniforms &u [[buffer(1)]]) {
    OccupancyGridVertex v = verts[vid];
    OccupancyGridOut out;
    out.position = u.mvp * float4(v.position, 1.0);
    out.color = float4(v.color) / 255.0;
    return out;
}

fragment float4 occupancyGridFragment(OccupancyGridOut in [[stage_in]]) {
    return in.color;
}
