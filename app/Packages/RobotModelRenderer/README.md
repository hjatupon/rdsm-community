# RobotModelRenderer

PBR rendering of articulated robots for ROS2 Studio (Layer 1). Poses a robot's links
by forward kinematics from a joint state and renders them with a Cook-Torrance
pipeline. Built on `MetalCore`.

## Quick start (≤30s)

```swift
import MetalCore
import RobotModelRenderer

let context = try MetalContext()
let renderer = try RobotModelRenderer(context: context)

// Build the kinematic tree (the renderer never parses URDF — Contract C7):
let model = RobotModel(links: links, joints: joints, rootLink: "base")
renderer.setModel(model, meshes: ["arm": mtkMesh])   // meshKey → MTKMesh

// On the render thread, inside your MTKView draw loop:
renderer.render(state: JointState(positions: ["j1": 0.6]), view: view, in: commandBuffer)
```

Meshes must use `RobotModelRenderer.meshVertexDescriptor` (position float3 @ 0,
normal float3 @ 1, interleaved in buffer 0).

## Demo

```bash
swift run --package-path Packages/RobotModelRenderer RobotModelDemo
```

A 4-link arm with three revolute joints; per-joint sliders drive the `JointState`
(the arm also auto-sweeps so an unattended run shows motion).

## Contracts & limits

- **C7** — the renderer consumes a `RobotModel` + `MTKMesh` dictionary; it does **not**
  parse URDF/XML. Building a `RobotModel` from URDF is M9's job; the demo constructs one
  directly.
- **Forward kinematics** — walked from the root, cached, recomputed only on state
  change. Accuracy is gated at ≤ 1e-4 vs an independent computation. Unreachable links
  and cycles are logged and skipped, never crash.
- **60fps PBR is PENDING-AS** — correctness, FK accuracy, depth, and the dark studio
  look are verified on Intel; the Apple-Silicon fps target and the Metal 4 PBR fast
  path are signed off separately.
