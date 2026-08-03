# Changelog

## 0.1.0 — 2026-05-30

- Initial release: `ChartPoint`, `ChartSeries`, `RingBuffer`, `ChartMode`, `ChartView`,
  `MetalChartRenderer`, `ChartUniforms`, `ChartingError`
- `RingBuffer<T>` — lock-free SPSC ring buffer, power-of-two capacity, push/drain/snapshot
  operations; drop-oldest policy when full; tested under concurrent producer + consumer
- `ChartSeries` — named, coloured series backed by a caller-owned `RingBuffer`
- `ChartMode` — `.metal` (line-strip GPU render), `.swiftCharts` (Apple Charts fallback),
  `.auto` (rate-based switch: ≥ 60 Hz → Metal, < 30 Hz → SwiftCharts, with hysteresis)
- `ChartView` — SwiftUI view that picks the right backend; Metal path wraps `MTKView`
  via `NSViewRepresentable`; SwiftCharts path resamples at 60 fps via a `Timer`
- `MetalChartRenderer` — compiles `Chart.metal` from source at init (same pattern as
  `RobotModelRenderer`); one instanced line-strip draw per series per frame; vertex
  buffer allocated per-frame from `MTLDevice` with `storageModeShared` (Intel + AS)
- `Chart.metal` — vertex shader maps `(t, value)` to NDC via `ChartUniforms`; fragment
  passes series colour through unchanged
- `ChartingDemo` — AppKit window, 4 × 100 Hz synthetic IMU-like series pushed from a
  detached Swift Task, rendered in `.metal` mode at 60 fps
- Tests: ring-buffer ordering, wrap-around, drop-oldest, drain, count/isEmpty,
  concurrent producer + consumer, chart-mode enum stability, series identity/sharing
- **Universal-Mac baseline**: builds and runs on Intel macOS 15.7; Apple Silicon perf
  characterization deferred to a batched QA pass
