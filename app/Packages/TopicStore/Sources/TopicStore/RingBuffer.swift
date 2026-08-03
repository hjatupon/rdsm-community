/// A fixed-capacity circular buffer with drop-oldest eviction.
///
/// Not thread-safe on its own — callers must synchronize (e.g. via an actor).
struct RingBuffer<T: Sendable>: Sendable {
    private var storage: [T?]
    private var head: Int = 0  // next write position
    private(set) var count: Int = 0
    let capacity: Int

    init(capacity: Int) {
        precondition(capacity > 0, "RingBuffer capacity must be > 0")
        self.capacity = capacity
        self.storage = Array(repeating: nil, count: capacity)
    }

    /// Appends `value`, evicting the oldest entry when full.
    mutating func push(_ value: T) {
        storage[head] = value
        head = (head + 1) % capacity
        if count < capacity { count += 1 }
    }

    /// Returns all stored values from oldest to newest.
    func all() -> [T] {
        guard count > 0 else { return [] }
        if count < capacity {
            return storage[0..<count].compactMap { $0 }
        }
        // Buffer is full: head points to the oldest slot
        let tail = storage[head..<capacity].compactMap { $0 }
        let wrap = storage[0..<head].compactMap { $0 }
        return tail + wrap
    }

    /// Returns the most recently pushed value, or `nil` if empty.
    var latest: T? {
        guard count > 0 else { return nil }
        let lastIdx = (head + capacity - 1) % capacity
        return storage[lastIdx]
    }

    mutating func clear() {
        storage = Array(repeating: nil, count: capacity)
        head = 0
        count = 0
    }
}
