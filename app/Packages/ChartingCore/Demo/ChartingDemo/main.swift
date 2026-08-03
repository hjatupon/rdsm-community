import AppKit
import ChartingCore
import MetalCore
import SwiftUI
import simd

// ChartingDemo — 4 synthetic IMU-like series at 100 Hz pushed from a background task.
// The producer runs on a detached Swift Task to validate the SPSC ring buffer under
// real concurrency. ChartView uses .metal mode so the line-strip renderer runs at 60fps.
// Verified on Intel macOS 15.7; Apple Silicon perf characterization deferred.

let sampleRate: Double = 100  // Hz
let windowSeconds: Double = 10

let seriesDefinitions: [(id: String, freq: Double, amp: Double, color: SIMD4<Float>)] = [
    ("accel_x", 0.8, 2.0, SIMD4<Float>(1.0, 0.35, 0.10, 1)),
    ("accel_y", 1.3, 1.5, SIMD4<Float>(0.25, 0.80, 0.25, 1)),
    ("accel_z", 2.1, 1.0, SIMD4<Float>(0.20, 0.55, 1.00, 1)),
    ("gyro_z",  0.5, 3.0, SIMD4<Float>(0.85, 0.75, 0.15, 1)),
]

let allSeries = seriesDefinitions.map {
    ChartSeries(id: $0.id, color: $0.color, capacity: 4096)
}

// MARK: - Producer

func startProducer() {
    Task.detached(priority: .userInitiated) {
        let startTime = Date().timeIntervalSince1970
        let interval = 1.0 / sampleRate
        var tick: Double = 0
        while true {
            let t = Date().timeIntervalSince1970
            let elapsed = t - startTime
            for (idx, def) in seriesDefinitions.enumerated() {
                let noise = Double.random(in: -0.05 ... 0.05)
                let v = def.amp * sin(2 * .pi * def.freq * elapsed) + noise
                allSeries[idx].buffer.push(ChartPoint(t: t, value: v))
            }
            tick += 1
            let nextFire = startTime + tick * interval
            let sleepNs = UInt64(max(0, (nextFire - Date().timeIntervalSince1970) * 1_000_000_000))
            try? await Task.sleep(nanoseconds: sleepNs)
        }
    }
}

// MARK: - App delegate & window

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        startProducer()

        let contentView = VStack(spacing: 0) {
            Text("ChartingCore Demo — 4 × 100 Hz IMU series (Metal mode)")
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.white)
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(white: 0.12))

            ChartView(series: allSeries, window: windowSeconds, mode: .metal)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(white: 0.08))

        let hosting = NSHostingView(rootView: contentView)
        hosting.frame = NSRect(x: 0, y: 0, width: 900, height: 340)

        let win = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 900, height: 340),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false)
        win.title = "ChartingCore Demo"
        win.contentView = hosting
        win.makeKeyAndOrderFront(nil)
        win.setIsVisible(true)
        self.window = win
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
