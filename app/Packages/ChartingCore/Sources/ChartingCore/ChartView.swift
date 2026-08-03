import Charts
import Foundation
import Logging
import MetalCore
import MetalKit
import SwiftUI

/// A time-series chart view that switches between a Metal line-strip renderer
/// (fast, handles ≥ 60 Hz) and Apple's SwiftCharts (lightweight, ≤ 60 Hz).
///
/// Usage:
/// ```swift
/// let s = ChartSeries(id: "velocity", color: .init(1, 0.3, 0, 1))
/// // push samples from your producer thread:
/// s.buffer.push(ChartPoint(t: Date().timeIntervalSince1970, value: reading))
/// // show the view:
/// ChartView(series: [s], window: 10.0, mode: .auto)
/// ```
public struct ChartView: View {
    private let series: [ChartSeries]
    private let window: TimeInterval
    private let mode: ChartMode

    public init(series: [ChartSeries], window: TimeInterval = 10.0, mode: ChartMode = .auto) {
        self.series = series
        self.window = window
        self.mode = mode
    }

    public var body: some View {
        Group {
            switch resolvedMode {
            case .metal:
                MetalChartViewRepresentable(series: series, window: window)
            case .swiftCharts, .auto:
                SwiftChartsView(series: series, window: window)
            }
        }
    }

    private var resolvedMode: ChartMode {
        switch mode {
        case .metal: return .metal
        case .swiftCharts: return .swiftCharts
        case .auto:
            // Simple heuristic: if any series has more than 60 recent points
            // in the last second, switch to Metal.
            let highRate = series.contains { s in
                let recent = s.buffer.snapshot(maxCount: 128)
                guard recent.count >= 2 else { return false }
                let duration = recent.last!.t - recent.first!.t
                return duration > 0 && Double(recent.count) / duration >= 60
            }
            return highRate ? .metal : .swiftCharts
        }
    }
}

// MARK: - Metal path (NSViewRepresentable wrapping MTKView)

struct MetalChartViewRepresentable: NSViewRepresentable {
    let series: [ChartSeries]
    let window: TimeInterval

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> MTKView {
        let view = MTKView()
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColor(red: 0.08, green: 0.08, blue: 0.08, alpha: 1)
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        view.preferredFramesPerSecond = 60

        do {
            let metalCtx = try MetalContext()
            let renderer = try MetalChartRenderer(context: metalCtx, pixelFormat: view.colorPixelFormat)
            renderer.series = series
            renderer.window = window
            context.coordinator.renderer = renderer
            view.delegate = renderer
        } catch {
            // Fall back gracefully — blank view; the SwiftCharts path is the safe fallback.
            Logger(subsystem: "studio.ros2", category: "charting")
                .error("Metal chart renderer init failed", fields: [
                    LogField(key: "error", value: error.localizedDescription)
                ])
        }
        return view
    }

    func updateNSView(_ view: MTKView, context: Context) {
        context.coordinator.renderer?.series = series
        context.coordinator.renderer?.window = window
    }

    class Coordinator {
        var renderer: MetalChartRenderer?
    }
}

// MARK: - SwiftCharts fallback path

struct SwiftChartsView: View {
    let series: [ChartSeries]
    let window: TimeInterval

    @State private var snapshots: [[ChartPoint]] = []
    @State private var now: Double = Date().timeIntervalSince1970
    private let timer = Timer.publish(every: 1.0 / 30, on: .main, in: .common).autoconnect()

    var body: some View {
        Chart {
            ForEach(Array(zip(series, snapshots)), id: \.0.id) { s, points in
                let color = Color(
                    red: Double(s.color.x),
                    green: Double(s.color.y),
                    blue: Double(s.color.z),
                    opacity: Double(s.color.w))
                ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                    LineMark(
                        x: .value("Time", point.t - now),
                        y: .value("Value", point.value))
                    .foregroundStyle(color)
                }
                .interpolationMethod(.linear)
            }
        }
        .chartXScale(domain: -window ... 0.0)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel {
                    if let t = value.as(Double.self) {
                        Text("\(Int(t))s")
                            .font(.caption2)
                    }
                }
            }
        }
        .background(Color(white: 0.08))
        .onReceive(timer) { _ in
            now = Date().timeIntervalSince1970
            refreshSnapshots()
        }
        .onAppear {
            now = Date().timeIntervalSince1970
            refreshSnapshots()
        }
    }

    private func refreshSnapshots() {
        snapshots = series.map { $0.buffer.snapshot(maxCount: 512) }
    }
}
