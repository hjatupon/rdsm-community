# RobotModelRenderer — Metal PBR Robot Rendering

## Key Types
- `RobotModelRenderer` — Metal PBR renderer, two pipelines (stride 24 box fallback, stride 32 loaded mesh)
- `ForwardKinematics` — BFS solver, joint motion models (revolute=quaternion, prismatic=translation)
- `JointState { positions: [String: Double] }` — snapshot per frame
- `Camera` — orbit camera (auto-orbit 0.4 rad/s), right-handed perspective

## Shaders
- `PBR.metal` — Cook-Torrance microfacet BRDF (GGX NDF, Smith geometry, Schlick Fresnel)
- Uniforms: mvp, model, albedo (tint*opacity), lightDirection, cameraPosition, metallic, roughness, ambient (0.08)

## Render Chain
```
metalWorld = rosToMetal * baseTransform * FK_world * visualOrigin.matrix * meshScale
mvp = viewProjection * metalWorld
```
- rosToMetal: [[0,0,1,0],[-1,0,0,0],[0,1,0,0],[0,0,0,1]]
- baseTransform: TF tree fixed frame → root link
- FK_world: forward kinematics output
- Scale must be last (mesh file units → metres)

## Gotchas
- Two render paths: loaded meshes (stride 32, real mesh pipeline) vs box fallback (stride 24)
- Hidden links via `hiddenLinks: Set<String>`, global opacity via `overrideOpacity`
- autoOrbitEnabled rotates azimuth at 0.4 rad/s
- model validation: unreachable links, cycles, skipped links
