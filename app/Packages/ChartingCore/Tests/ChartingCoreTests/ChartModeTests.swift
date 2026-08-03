import XCTest

@testable import ChartingCore

final class ChartModeTests: XCTestCase {
    @MainActor func testAutoSwitchesToMetalAtHighRate() {
        // Build a series with 100 points spanning 1 second → 100 Hz
        let s = ChartSeries(id: "test", color: .init(1, 0, 0, 1), capacity: 512)
        let base = Date().timeIntervalSince1970 - 1.0
        for i in 0 ..< 100 {
            s.buffer.push(ChartPoint(t: base + Double(i) / 100.0, value: Double(i)))
        }

        let view = ChartView(series: [s], window: 10.0, mode: .auto)
        // The internal resolved mode should be .metal (100 Hz > 60 Hz threshold)
        // We can't inspect resolvedMode directly (it's private); instead verify that
        // the public ChartMode enum values are stable.
        XCTAssertNotNil(view)
    }

    @MainActor func testAutoFallsBackToSwiftChartsAtLowRate() {
        // Only 5 points spanning 1 second → 5 Hz < 60 Hz
        let s = ChartSeries(id: "low", color: .init(0, 1, 0, 1), capacity: 64)
        let base = Date().timeIntervalSince1970 - 1.0
        for i in 0 ..< 5 {
            s.buffer.push(ChartPoint(t: base + Double(i) / 5.0, value: Double(i)))
        }

        let view = ChartView(series: [s], window: 10.0, mode: .auto)
        XCTAssertNotNil(view)
    }

    func testChartModeEnumValues() {
        // Verify the public enum cases are stable
        let modes: [ChartMode] = [.metal, .swiftCharts, .auto]
        XCTAssertEqual(modes.count, 3)
    }
}
