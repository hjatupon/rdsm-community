# MetalCore

> M4 · Layer 1 · ROS2 Studio · Depends: Logging

The GPU foundation every renderer builds on: one shared `MetalContext` (device +
command queue), a power-of-two `ResourcePool` for per-frame buffer reuse, and a
fluent `RenderPassBuilder`. Contract C4 — one `MetalContext` per app, created in
the composition root and shared; encoders stay single-threaded.

## Quick start (< 30 seconds)

```swift
import MetalCore

let context = try MetalContext()                 // throws .noDevice on headless CI
let pool = ResourcePool(context: context)

let buffer = pool.acquireBuffer(length: 1_024, options: .storageModeShared)
// … fill + encode …
pool.release(buffer)                             // returns it to the bucket for reuse

let pass = RenderPassBuilder()
    .colorAttachment(texture, clear: MTLClearColor(red: 0.05, green: 0.05, blue: 0.07, alpha: 1),
                     load: .clear, store: .store)
    .build()
```

## Run the demo

```bash
swift run --package-path Packages/MetalCore MetalCoreDemo
```

Opens an `MTKView` window, clears every frame to the dark-theme background, logs
the average frame interval, and auto-quits after ~3s.

## Run tests

```bash
swift test --package-path Packages/MetalCore --parallel
```

Tests early-return on machines without a Metal device, so headless CI stays green.

## Performance

`120fps on ProMotion` is **PENDING-AS** — the dev machine is Intel, where Metal
is correct but the Apple-Silicon frame targets cannot be measured. Correctness,
buffer reuse, and a stable leak-free loop are verified here; fps is signed off
later on an M-series Mac.

## Version

`0.1.0` — initial release
