import XCTest

@testable import ChartingCore

final class RingBufferTests: XCTestCase {
    func testRoundsToPowerOfTwo() {
        XCTAssertEqual(RingBuffer<Int>(capacity: 3).capacity, 4)
        XCTAssertEqual(RingBuffer<Int>(capacity: 4).capacity, 4)
        XCTAssertEqual(RingBuffer<Int>(capacity: 5).capacity, 8)
    }

    func testPushAndSnapshot() {
        let buf = RingBuffer<Int>(capacity: 8)
        buf.push(1); buf.push(2); buf.push(3)
        let snap = buf.snapshot(maxCount: 8)
        XCTAssertEqual(snap, [1, 2, 3])
    }

    func testSnapshotRespectsMaxCount() {
        let buf = RingBuffer<Int>(capacity: 16)
        for i in 0 ..< 10 { buf.push(i) }
        let snap = buf.snapshot(maxCount: 4)
        XCTAssertEqual(snap.count, 4)
        // Most-recent 4: 6,7,8,9
        XCTAssertEqual(snap, [6, 7, 8, 9])
    }

    func testDropOldestOnWrapAround() {
        let buf = RingBuffer<Int>(capacity: 4)
        // Push 6 items into a capacity-4 ring: items 0,1 should be overwritten
        for i in 0 ..< 6 { buf.push(i) }
        let snap = buf.snapshot(maxCount: 4)
        // Only the latest 4 writes survived
        XCTAssertEqual(snap, [2, 3, 4, 5])
    }

    func testDrain() {
        let buf = RingBuffer<Int>(capacity: 8)
        buf.push(10); buf.push(20); buf.push(30)
        var out: [Int] = []
        buf.drain(into: &out)
        XCTAssertEqual(out, [10, 20, 30])
        // Second drain should yield nothing
        var out2: [Int] = []
        buf.drain(into: &out2)
        XCTAssertTrue(out2.isEmpty)
    }

    func testIsEmpty() {
        let buf = RingBuffer<Int>(capacity: 4)
        XCTAssertTrue(buf.isEmpty)
        buf.push(1)
        XCTAssertFalse(buf.isEmpty)
    }

    func testCount() {
        let buf = RingBuffer<Int>(capacity: 8)
        XCTAssertEqual(buf.count, 0)
        buf.push(1); buf.push(2)
        XCTAssertEqual(buf.count, 2)
    }

    // MARK: - Concurrency

    func testConcurrentProducerAndConsumer() async {
        let buf = RingBuffer<Int>(capacity: 1024)
        let iterations = 5000

        await withTaskGroup(of: Void.self) { group in
            // Producer task
            group.addTask {
                for i in 0 ..< iterations { buf.push(i) }
            }
            // Consumer task — just snapshot; verifies no crash
            group.addTask {
                var consumed = 0
                while consumed < iterations {
                    let snap = buf.snapshot(maxCount: 64)
                    consumed += snap.count
                    await Task.yield()
                }
            }
        }
        // After producer finishes, the ring holds the last `capacity` values.
        let final = buf.snapshot(maxCount: 1024)
        XCTAssertFalse(final.isEmpty)
    }
}
