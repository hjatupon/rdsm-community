# Changelog

## 0.1.0 — 2026-05-29

- Initial release: `PointCloudFrame`, `Axis`, `PointColorMode`, `PointCloudRenderer`
- `PointCloudFrame` — packed float3 positions + optional intensity/color channels as
  raw `Data` (allocation-free ingest); `hasValidLayout` rejects malformed frames
- `PointCloudRenderer` — thread-safe `update(frame:)` (lock-protected latest-frame
  slot, Contract C5), render-thread `render(view:mode:in:)`; GPU point-sprite pipeline
- Color modes: `.axis`, `.intensity(min:max:)`, `.rgb`, `.constant` — computed in-shader,
  with the CPU mirror (`PointColoring`) unit-tested
- LOD: clouds above 500k points stride-decimated so each cycle uploads ≤ 16 MB;
  position/color buffers recycled via `MetalCore.ResourcePool`, released on GPU completion
- Internal orbit `Camera` value type; renderer auto-orbits so the demo needs no camera input
- `PointCloudDemo` — 1M Lissajous points, orbiting, cycling all color modes, fps readout
- Tests: frame layout validation, LOD thresholds, color-mode mapping, 16 MB cycle budget,
  concurrent ingest safety
- **60fps @ 1M points is PENDING-AS** — Intel dev machine verifies correctness + the
  ≤16MB cycle budget (Milestone B structurally met); Apple-Silicon fps signed off later.
  Metal 4 mesh-shader / compute-cull fast paths deferred to that sign-off.
