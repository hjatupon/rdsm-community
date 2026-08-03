#include <metal_stdlib>
using namespace metal;

// Mirrors Swift `struct RobotUniforms` — field order and offsets must match exactly.
struct RobotUniforms {
    float4x4 mvp;
    float4x4 model;
    float4 albedo;
    float4 lightDirection; // xyz, world space (points from light toward scene)
    float4 cameraPosition; // xyz, world space
    float metallic;
    float roughness;
    float ambient;
    float pad;
};

struct VertexIn {
    float3 position [[attribute(0)]];
    float3 normal [[attribute(1)]];
};

struct VertexOut {
    float4 position [[position]];
    float3 worldPosition;
    float3 worldNormal;
};

vertex VertexOut pbrVertex(VertexIn in [[stage_in]], constant RobotUniforms &u [[buffer(1)]]) {
    VertexOut out;
    float4 world = u.model * float4(in.position, 1.0);
    out.position = u.mvp * float4(in.position, 1.0);
    out.worldPosition = world.xyz;
    out.worldNormal = normalize((u.model * float4(in.normal, 0.0)).xyz);
    return out;
}

constant float PI = 3.14159265359;

static float distributionGGX(float3 n, float3 h, float roughness) {
    float a = roughness * roughness;
    float a2 = a * a;
    float ndoth = max(dot(n, h), 0.0);
    float denom = (ndoth * ndoth * (a2 - 1.0) + 1.0);
    return a2 / max(PI * denom * denom, 1e-4);
}

static float geometrySchlick(float ndotv, float roughness) {
    float r = roughness + 1.0;
    float k = (r * r) / 8.0;
    return ndotv / (ndotv * (1.0 - k) + k);
}

static float3 fresnelSchlick(float cosTheta, float3 f0) {
    return f0 + (1.0 - f0) * pow(clamp(1.0 - cosTheta, 0.0, 1.0), 5.0);
}

fragment float4 pbrFragment(VertexOut in [[stage_in]], constant RobotUniforms &u [[buffer(0)]]) {
    float3 n = normalize(in.worldNormal);
    float3 v = normalize(u.cameraPosition.xyz - in.worldPosition);
    float3 l = normalize(-u.lightDirection.xyz);
    float3 h = normalize(v + l);

    float3 albedo = u.albedo.rgb;
    float3 f0 = mix(float3(0.04), albedo, u.metallic);

    float ndf = distributionGGX(n, h, u.roughness);
    float ndotv = max(dot(n, v), 1e-4);
    float ndotl = max(dot(n, l), 0.0);
    float g = geometrySchlick(ndotv, u.roughness) * geometrySchlick(ndotl, u.roughness);
    float3 f = fresnelSchlick(max(dot(h, v), 0.0), f0);

    float3 specular = (ndf * g * f) / max(4.0 * ndotv * ndotl, 1e-4);
    float3 kd = (1.0 - f) * (1.0 - u.metallic);

    float3 lit = (kd * albedo / PI + specular) * ndotl;
    float3 ambient = u.ambient * albedo;
    float3 color = ambient + lit;

    // Simple Reinhard tone-map + gamma for a clean studio look.
    color = color / (color + 1.0);
    color = pow(color, float3(1.0 / 2.2));
    return float4(color, u.albedo.w);
}
