# RobotModelCore Changelog

## 0.1.0 — 2026-05-30

Initial release. Types extracted from `RobotModelRenderer` 0.1.0 to break the
Layer-2 (URDFParser) → Layer-1 (RobotModelRenderer+Metal) dependency inversion.

- `RobotModel` — kinematic tree (links + joints + rootLink)
- `Link` — rigid body with optional meshKey
- `Joint` — parent→child connection with JointType, axis, origin Transform
- `JointType` — fixed, revolute, prismatic, continuous, floating, planar
- `Transform` — Float-precision rigid transform (translation + simd_quatf)
