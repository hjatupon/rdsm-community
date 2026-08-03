#include <metal_stdlib>
using namespace metal;

struct MeshMapVertex {
    packed_float3 position;
    packed_float3 normal;
    uchar4 color;
};

struct MeshMapUniforms {
    float4x4 mvp;
    packed_float3 lightDir;
    float ambient;
};

struct MeshMapOut {
    float4 position [[position]];
    float4 color;
    float3 normal;
};

vertex MeshMapOut meshMapVertex(uint vid [[vertex_id]],
                                device const MeshMapVertex *verts [[buffer(0)]],
                                constant MeshMapUniforms &u [[buffer(1)]]) {
    MeshMapVertex v = verts[vid];
    MeshMapOut out;
    out.position = u.mvp * float4(v.position, 1.0);
    out.normal = normalize(v.normal);
    out.color = float4(v.color) / 255.0;
    return out;
}

fragment float4 meshMapFragment(MeshMapOut in [[stage_in]],
                                constant MeshMapUniforms &u [[buffer(1)]]) {
    float3 n = normalize(in.normal);
    float diff = max(dot(n, normalize(u.lightDir)), 0.0);
    float3 lit = in.color.rgb * (u.ambient + (1.0 - u.ambient) * diff);
    return float4(lit, in.color.a);
}
