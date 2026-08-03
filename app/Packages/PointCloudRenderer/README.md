# PointCloudRenderer

GPU point-cloud rendering for ROS2 Studio (Layer 1). Ingest frames from any thread,
render colored point sprites on the render thread. Built on `MetalCore`.

## Quick start (≤30s)

```swift
import MetalCore
import PointCloudRenderer

let context = try MetalContext()
let renderer = try PointCloudRenderer(context: context)

// Ingest from any thread:
renderer.update(frame: PointCloudFrame(
    pointCount: n,
    positions: positionsData,   // packed float3 × n (12 bytes/point)
    intensities: nil,
    colors: nil))

// On the render thread, inside your MTKView draw loop:
renderer.render(view: view, mode: .axis(.z), in: commandBuffer)
```

## Color modes

- `.axis(.x/.y/.z)` — ramp by coordinate, normalized to the cloud's bounds
- `.intensity(min:max:)` — ramp by the intensity channel, clamped
- `.rgb` — use the per-point color channel
- `.constant(SIMD4<Float>)` — flat color

## Demo (Milestone B)

```bash
swift run --package-path Packages/PointCloudRenderer PointCloudDemo
```

Renders 1,000,000 Lissajous points, auto-orbiting, cycling every color mode.

## Contracts & limits

- **C5** — `update(frame:)` is thread-safe; `render(view:mode:in:)` is render-thread only.
- **Buffer budget** — clouds above 500k points are stride-decimated so each render
  cycle uploads ≤ 16 MB; buffers are recycled through `MetalCore.ResourcePool`.
- **60fps @ 1M points is PENDING-AS** — verified for correctness and the ≤16MB cycle
  on Intel; the Apple-Silicon fps target is signed off separately. The Metal 4
  mesh-shader fast path is deferred; the point-primitive pipeline is correct on macOS 15+.
