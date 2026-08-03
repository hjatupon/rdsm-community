# MetalCore — GPU Infrastructure

## Key Types
- `MetalContext` (@unchecked Sendable) — single MTLDevice + MTLCommandQueue, makeBuffer, loadShaderLibrary
- `ResourcePool` (NSLock) — power-of-two bucketed MTLBuffer reuse, max 4 per bucket
- `RenderPassBuilder` — fluent builder: .colorAttachment(texture, clear, load, store) → MTLRenderPassDescriptor

## Files
- `MetalContext.swift` (60 lines), `ResourcePool.swift` (68 lines), `RenderPassBuilder.swift` (63 lines), `MetalError.swift`

## Errors
- noDevice, bufferAllocationFailed, libraryNotFound (shader not in SPM bundle), shaderCompilationFailed

## Gotchas
- Shaders loaded from SPM resource bundle via Bundle.module (not Xcode default library)
- loadShaderLibrary fallback: try Bundle.module first, then source compile
- Shared by all renderers (PointCloudRenderer, RobotModelRenderer, ChartingCore)
