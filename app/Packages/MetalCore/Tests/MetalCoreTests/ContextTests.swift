import Metal
import Testing
@testable import MetalCore

/// Returns a context, or nil on a headless machine (no Metal device). Tests that
/// need a GPU early-return when nil so CI without a GPU stays green.
func makeContextOrSkip() -> MetalContext? {
    try? MetalContext()
}

@Suite("MetalContext")
struct ContextTests {
    @Test
    func `Creates a device and command queue when a GPU exists`() {
        guard let context = makeContextOrSkip() else { return }
        #expect(!context.device.name.isEmpty)
    }

    @Test
    func `makeBuffer returns a buffer of at least the requested length`() throws {
        guard let context = makeContextOrSkip() else { return }
        let buffer = try context.makeBuffer(length: 1024, options: .storageModeShared)
        #expect(buffer.length >= 1024)
    }

    @Test
    func `makeBuffer with non-positive length throws bufferAllocationFailed`() throws {
        guard let context = makeContextOrSkip() else { return }
        #expect(throws: MetalError.bufferAllocationFailed(length: 0)) {
            _ = try context.makeBuffer(length: 0, options: .storageModeShared)
        }
    }

    @Test
    func `Loading a missing shader library throws libraryNotFound`() throws {
        guard let context = makeContextOrSkip() else { return }
        #expect(throws: MetalError.libraryNotFound("does-not-exist")) {
            _ = try context.loadShaderLibrary(named: "does-not-exist", bundle: .main)
        }
    }
}
