# Changelog

## 0.2.0 — 2026-05-30

- `RobotModel`, `Link`, `Joint`, `JointType`, `Transform` moved to `RobotModelCore`
  (new Layer-1 package) so `URDFParser` (M9, Layer 2) can depend on the value types
  without pulling in Metal. Source compatibility preserved via `@_exported import`.
- `RobotModelRenderer` now depends on `RobotModelCore`.

## 0.1.0 — 2026-05-30

- Initial release: `Link`, `Joint`, `JointType`, `RobotModel`, `JointState`, `Transform`,
  `RobotModelRenderer`
- `Transform` — translation + unit-quaternion rigid transform; Hashable over components
- Forward kinematics — tree walk from root composing joint origins + state-driven motion
  (revolute/continuous rotate, prismatic translate, fixed/floating/planar static);
  cached and recomputed only on state change; accuracy gated ≤ 1e-4
- `RobotModelRenderer` — Cook-Torrance PBR pipeline (directional light + ambient,
  Reinhard tone-map), depth-tested, dark studio background; **does not parse URDF** (C7)
- `setModel(_:meshes:)` — validates the tree (logs unreachable links, cycles) and warns
  about + skips links whose `meshKey` has no mesh; rendering proceeds
- `meshVertexDescriptor` — the position+normal interleaved layout meshes must use
- `RobotModelDemo` — 4-link arm, three revolute joints, per-joint sliders + auto-sweep
- Tests: FK accuracy vs independent computation, FK cache hit/miss, unknown-child skip,
  cycle detection, missing-mesh skip, unreachable-link detection
- **60fps PBR is PENDING-AS** — Intel dev machine verifies correctness + FK accuracy;
  Apple-Silicon fps and the Metal 4 PBR fast path signed off later.
- Shaders compiled from source at init (SwiftPM copies `.metal` verbatim).
