# ChartingCore

Metal-backed time-series chart for ROS2 topics at ≥ 60 Hz. Handles high-rate sensor
data (IMU, LiDAR scan statistics, velocity commands) that would overwhelm SwiftCharts.

**Universal-Mac baseline** — builds and runs on Intel macOS 15+ and Apple Silicon.
Apple Silicon perf characterization deferred to a batched QA pass.

---

## Quick start (≤ 30 seconds)

```swift
import ChartingCore
import SwiftUI

// 1. Create a series (one per data channel)
let velX = ChartSeries(id: "vel_x", color: .init(1, 0.3, 0.1, 1))

// 2. Push samples from your producer thread (e.g. Transport subscription callback)
velX.buffer.push(ChartPoint(t: Date().timeIntervalSince1970, value: reading))

// 3. Show in a SwiftUI view
ChartView(series: [velX], window: 10.0, mode: .auto)
```

---

## SPSC contract

`RingBuffer` is a **Single-Producer / Single-Consumer** (SPSC) lock-free ring buffer.

- **Producer thread**: calls `push(_:)` — typically your Transport callback or timer
- **Consumer thread**: calls `snapshot(maxCount:)` or `drain(into:)` — the render thread

Never call `push` and `drain`/`snapshot` from the same thread concurrently from different
goroutines. The SPSC guarantee is the only thread-safety guarantee provided. There is no
internal lock, so violating this results in undefined behaviour.

When the buffer is full, the **oldest sample is overwritten** (drop-oldest policy).

---

## Modes

| Mode | When to use |
|------|-------------|
| `.metal` | Always use the GPU line-strip renderer. Best for ≥ 60 Hz data. |
| `.swiftCharts` | Always use Apple Charts (lightweight, ≤ 60 Hz). |
| `.auto` | Switch based on observed sample rate. Default. |

---

## Dependencies

- **MetalCore** (Layer 1, same project) — `MetalContext`
- **Logging** (Layer 0, same project) — `LoggerProtocol`
- **Metal**, **MetalKit**, **SwiftUI**, **Charts** (Apple SDK)
