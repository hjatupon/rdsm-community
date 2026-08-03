import Foundation

/// Lock-free SPSC (single-producer / single-consumer) ring buffer.
///
/// **Ownership contract:** exactly one "producer" thread calls `push(_:)`;
/// exactly one "consumer" thread calls `snapshot(into:)` or reads `count`.
/// Violating this is undefined behaviour — there is no internal lock.
///
/// Capacity is rounded up to the next power of two so the index mask
/// `capacity - 1` avoids modulo.
public final class RingBuffer<T: Sendable>: @unchecked Sendable {
    private let storage: UnsafeMutablePointer<T?>
    private let mask: Int
    public let capacity: Int

    // Written only by producer; read by both (relaxed okay: single producer).
    private var _writeIndex: Int = 0
    // Written only by consumer; read by both (relaxed okay: single consumer).
    private var _readIndex: Int = 0

    public init(capacity: Int) {
        precondition(capacity > 0, "capacity must be > 0")
        let size = capacity.nextPowerOfTwo
        self.capacity = size
        self.mask = size - 1
        self.storage = .allocate(capacity: size)
        self.storage.initialize(repeating: nil, count: size)
    }

    deinit {
        storage.deinitialize(count: capacity)
        storage.deallocate()
    }

    /// Number of items currently available to the consumer.
    public var count: Int { max(0, _writeIndex - _readIndex) }

    /// True when the buffer holds no items.
    public var isEmpty: Bool { _writeIndex == _readIndex }

    /// Push a sample from the producer thread.
    /// When full, the oldest item is overwritten (drop-oldest policy).
    public func push(_ value: T) {
        let wi = _writeIndex
        storage[wi & mask] = value
        // Use OSAtomicAdd to get a memory barrier on x86 and arm.
        OSAtomicAdd64(1, &writeCount)
        _writeIndex = wi + 1
    }

    /// Append all available samples into `out` and advance the read index.
    /// Call from the consumer thread only.
    public func drain(into out: inout [T]) {
        let wi = _writeIndex
        let ri = _readIndex
        guard wi > ri else { return }
        let available = wi - ri
        out.reserveCapacity(out.count + available)
        for i in ri ..< wi {
            if let v = storage[i & mask] {
                out.append(v)
            }
        }
        _readIndex = wi
    }

    /// Return a snapshot of up to `maxCount` most-recent samples without
    /// advancing the read index. Safe to call from the consumer thread.
    public func snapshot(maxCount: Int) -> [T] {
        let wi = _writeIndex
        let ri = _readIndex
        let available = max(0, wi - ri)
        let take = min(available, maxCount)
        guard take > 0 else { return [] }
        var result: [T] = []
        result.reserveCapacity(take)
        let start = wi - take
        for i in start ..< wi {
            if let v = storage[i & mask] {
                result.append(v)
            }
        }
        return result
    }

    // Dummy field so OSAtomicAdd64 has an Int64 to operate on per push.
    // This is the memory-barrier mechanism on both x86 and ARM.
    private var writeCount: Int64 = 0
}

private extension Int {
    var nextPowerOfTwo: Int {
        guard self > 1 else { return 1 }
        var n = self - 1
        n |= n >> 1; n |= n >> 2; n |= n >> 4; n |= n >> 8; n |= n >> 16; n |= n >> 32
        return n + 1
    }
}
