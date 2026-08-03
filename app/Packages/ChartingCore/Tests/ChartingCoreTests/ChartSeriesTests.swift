import XCTest
import simd

@testable import ChartingCore

final class ChartSeriesTests: XCTestCase {
    func testIdentityAndColor() {
        let color = SIMD4<Float>(0.2, 0.5, 0.8, 1.0)
        let s = ChartSeries(id: "imu_x", color: color)
        XCTAssertEqual(s.id, "imu_x")
        XCTAssertEqual(s.color, color)
    }

    func testBufferSharing() {
        // Two references to the same ChartSeries must share the same underlying buffer.
        let s = ChartSeries(id: "shared", color: .init(1, 1, 1, 1))
        let s2 = s  // struct copy, but RingBuffer is a class reference
        s.buffer.push(ChartPoint(t: 1.0, value: 42.0))
        let snap = s2.buffer.snapshot(maxCount: 10)
        XCTAssertEqual(snap.count, 1)
        XCTAssertEqual(snap[0].value, 42.0, accuracy: 1e-9)
    }

    func testCustomCapacity() {
        let s = ChartSeries(id: "high-rate", color: .init(1, 0, 0, 1), capacity: 8192)
        XCTAssertGreaterThanOrEqual(s.buffer.capacity, 8192)
    }

    func testChartPointTimestamp() {
        let t = Date().timeIntervalSince1970
        let pt = ChartPoint(t: t, value: 3.14)
        XCTAssertEqual(pt.t, t, accuracy: 1e-9)
        XCTAssertEqual(pt.value, 3.14, accuracy: 1e-9)
    }
}
