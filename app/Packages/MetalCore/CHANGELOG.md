# Changelog

## 0.1.0 — 2026-05-29

- Initial release: `MetalContext`, `ResourcePool`, `RenderPassBuilder`, `MetalError`
- `MetalContext` — shared `MTLDevice` + `MTLCommandQueue` (Contract C4, one per app);
  `makeBuffer`, `loadShaderLibrary(named:bundle:)`; `.noDevice` on headless CI
- `ResourcePool` — power-of-two bucketed `MTLBuffer` free list, `NSLock`-guarded,
  acquire/release with debug hit/miss logging; per-frame reuse instead of fresh allocs
- `RenderPassBuilder` — fluent color/depth attachment builder → `MTLRenderPassDescriptor`
- Public API throws only `MetalError` — no raw Metal `NSError` escapes
- `Passthrough.metal` full-screen shader resource via `.process("Shaders")`
- `MetalCoreDemo` — AppKit-hosted `MTKView`, clears to dark theme, logs frame interval,
  auto-quits ~3s
- Tests: device/queue creation (skip-if-nil), buffer length + bad-length throw,
  bucket rounding, acquire→release→acquire reuse, concurrent TaskGroup safety
- **120fps on ProMotion is PENDING-AS** — Intel dev machine verifies correctness +
  stable loop; Apple-Silicon fps signed off later
