# RobotModelCore

Pure-value-type layer shared by `RobotModelRenderer` (M6, renders) and `URDFParser` (M9, parses). No GPU, no Metal, no networking.

## Types

| Type | Purpose |
|---|---|
| `RobotModel` | Kinematic tree: links, joints, rootLink |
| `Link` | Rigid body name + optional meshKey |
| `Joint` | Parent→child edge: type, axis, origin |
| `JointType` | fixed / revolute / prismatic / continuous / floating / planar |
| `Transform` | Float-precision rigid transform (SIMD3<Float> + simd_quatf) |

## Quick Start

```swift
import RobotModelCore

let origin = Transform(translation: SIMD3(0, 0.5, 0))
let model = RobotModel(
    links: [Link(name: "base", meshKey: "base_mesh"), Link(name: "link1", meshKey: "arm_mesh")],
    joints: [Joint(name: "j1", parent: "base", child: "link1", type: .revolute, axis: SIMD3(0, 0, 1), origin: origin)],
    rootLink: "base"
)
```

## Notes

- `Transform` here is Float-precision for Metal rendering. `TFTree.Transform` (M13) is Double-precision for interpolation accuracy — distinct types.
- `RobotModelRenderer` re-exports these types via `@_exported import RobotModelCore`.
