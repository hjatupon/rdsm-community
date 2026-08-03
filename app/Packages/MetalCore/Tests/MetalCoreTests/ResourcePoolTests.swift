import Metal
import Testing
@testable import MetalCore

@Suite("ResourcePool")
struct ResourcePoolTests {
    @Test
    func `Rounds lengths up to the next power-of-two bucket`() {
        #expect(ResourcePool.bucket(for: 0) == 1)
        #expect(ResourcePool.bucket(for: 1) == 1)
        #expect(ResourcePool.bucket(for: 2) == 2)
        #expect(ResourcePool.bucket(for: 3) == 4)
        #expect(ResourcePool.bucket(for: 4) == 4)
        #expect(ResourcePool.bucket(for: 5) == 8)
        #expect(ResourcePool.bucket(for: 100) == 128)
        #expect(ResourcePool.bucket(for: 256) == 256)
        #expect(ResourcePool.bucket(for: 257) == 512)
    }

    @Test
    func `acquire → release → acquire reuses the same buffer`() {
        guard let context = makeContextOrSkip() else { return }
        let pool = ResourcePool(context: context)
        let first = pool.acquireBuffer(length: 100, options: .storageModeShared)
        let firstPtr = first.contents()
        pool.release(first)
        let second = pool.acquireBuffer(length: 100, options: .storageModeShared)
        // Same bucket, returned to the free list → same underlying buffer.
        #expect(second.contents() == firstPtr)
    }

    @Test
    func `A miss after the pool is empty allocates a fresh buffer`() {
        guard let context = makeContextOrSkip() else { return }
        let pool = ResourcePool(context: context)
        let first = pool.acquireBuffer(length: 100, options: .storageModeShared)
        let second = pool.acquireBuffer(length: 100, options: .storageModeShared)
        // Nothing released between the two acquires → distinct buffers.
        #expect(first.contents() != second.contents())
    }

    @Test
    func `Concurrent acquire/release from a TaskGroup is safe`() async {
        guard let context = makeContextOrSkip() else { return }
        let pool = ResourcePool(context: context)
        await withTaskGroup(of: Void.self) { group in
            for _ in 0 ..< 200 {
                group.addTask {
                    let buffer = pool.acquireBuffer(length: Int.random(in: 1 ... 4096), options: .storageModeShared)
                    pool.release(buffer)
                }
            }
        }
        // The pool is still usable after the stress.
        let buffer = pool.acquireBuffer(length: 64, options: .storageModeShared)
        #expect(buffer.length >= 64)
    }
}
