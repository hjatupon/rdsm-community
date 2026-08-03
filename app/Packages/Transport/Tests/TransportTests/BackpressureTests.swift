import Foundation
import Testing
@testable import Transport

/// Validates the drop-oldest, bounded-buffer semantics that `ConnectionActor.deliver`
/// relies on: `AsyncStream` with `.bufferingNewest(N)` keeps the newest N and reports
/// drops via the yield result (which we log as a warning).
@Suite("Backpressure: bounded drop-oldest buffer")
struct BackpressureTests {
    @Test
    func `Overflowing a bufferingNewest stream keeps newest and reports drops`() async {
        let capacity = 4
        let (stream, continuation) = AsyncStream.makeStream(
            of: Int.self, bufferingPolicy: .bufferingNewest(capacity))

        var dropCount = 0
        for i in 0 ..< 10 {
            let result = continuation.yield(i)
            if case .dropped = result { dropCount += 1 }
        }
        continuation.finish()

        var received: [Int] = []
        for await value in stream {
            received.append(value)
        }

        // Newest `capacity` values survive; everything older was dropped.
        #expect(received == [6, 7, 8, 9])
        #expect(dropCount == 6)
        #expect(received.count == capacity)
    }

    @Test
    func `Slow consumer never blocks the producer (bounded growth)`() async {
        let (stream, continuation) = AsyncStream.makeStream(
            of: Int.self, bufferingPolicy: .bufferingNewest(256))
        // Produce far more than the buffer without consuming — must not grow unboundedly.
        for i in 0 ..< 10000 {
            _ = continuation.yield(i)
        }
        continuation.finish()

        var count = 0
        for await _ in stream {
            count += 1
        }
        #expect(count <= 256) // capped at buffer size
    }
}
