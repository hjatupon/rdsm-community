import AppKit
import Foundation
import MetalCore
import MetalKit
import PointCloudRenderer
import QuartzCore
import simd

// PointCloudDemo — Milestone B: a 1,000,000-point Lissajous cloud rendered with the
// shared MetalContext, auto-orbiting, cycling through every PointColorMode, with an
// fps readout. On Intel this verifies correctness + the ≤16MB cycle budget; the
// 60fps @ 1M target is PENDING-AS (Apple-Silicon sign-off).

let pointCount = 1_000_000

func makeCloud() -> PointCloudFrame {
    var positions = [Float]()
    positions.reserveCapacity(pointCount * 3)
    var intensities = [Float]()
    intensities.reserveCapacity(pointCount)
    var colors = [UInt8]()
    colors.reserveCapacity(pointCount * 4)

    for i in 0 ..< pointCount {
        let t = Float(i) / Float(pointCount) * Float.pi * 2
        let a: Float = 3, b: Float = 2, c: Float = 5
        let x = sin(a * t + 1.5) * 1.4
        let y = sin(b * t) * 1.4
        let z = sin(c * t) * 1.4
        positions.append(x)
        positions.append(y)
        positions.append(z)
        let intensity = Float(i) / Float(pointCount)
        intensities.append(intensity)
        colors.append(UInt8(max(0, min(255, (x * 0.5 + 0.5) * 255))))
        colors.append(UInt8(max(0, min(255, (y * 0.5 + 0.5) * 255))))
        colors.append(UInt8(max(0, min(255, (z * 0.5 + 0.5) * 255))))
        colors.append(255)
    }

    return PointCloudFrame(
        pointCount: pointCount,
        positions: positions.withUnsafeBytes { Data($0) },
        intensities: intensities.withUnsafeBytes { Data($0) },
        colors: colors.withUnsafeBytes { Data($0) })
}

final class Renderer: NSObject, MTKViewDelegate {
    private let context: MetalContext
    private let cloud: PointCloudRenderer
    private var frameCount = 0
    private var lastTimestamp = CACurrentMediaTime()
    private var intervalSum = 0.0

    private let modes: [(String, PointColorMode)] = [
        ("axis(z)", .axis(.z)),
        ("intensity", .intensity(min: 0, max: 1)),
        ("rgb", .rgb),
        ("constant", .constant(SIMD4(0.2, 0.8, 1.0, 1.0))),
    ]
    private var modeIndex = 0
    private var lastModeSwitch = CACurrentMediaTime()

    init(context: MetalContext) throws {
        self.context = context
        cloud = try PointCloudRenderer(context: context)
        super.init()
        cloud.update(frame: makeCloud())
        print("PointCloudDemo — \(pointCount) points uploaded; cycling color modes")
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        let now = CACurrentMediaTime()
        if now - lastModeSwitch > 1.5 {
            modeIndex = (modeIndex + 1) % modes.count
            lastModeSwitch = now
            print("  color mode → \(modes[modeIndex].0)")
        }

        guard let commandBuffer = context.commandQueue.makeCommandBuffer() else { return }
        cloud.render(view: view, mode: modes[modeIndex].1, in: commandBuffer)
        if let drawable = view.currentDrawable { commandBuffer.present(drawable) }
        commandBuffer.commit()

        intervalSum += now - lastTimestamp
        lastTimestamp = now
        frameCount += 1
        if frameCount % 60 == 0 {
            let avgMs = (intervalSum / Double(frameCount)) * 1000
            let fps = avgMs > 0 ? 1000 / avgMs : 0
            print("  \(frameCount) frames  avg \(String(format: "%.2f", avgMs)) ms  ~\(String(format: "%.0f", fps)) fps")
        }
    }

    var frames: Int { frameCount }
}

do {
    let context = try MetalContext()
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)

    let view = MTKView(frame: NSRect(x: 0, y: 0, width: 900, height: 700), device: context.device)
    view.clearColor = MTLClearColor(red: 0.05, green: 0.05, blue: 0.07, alpha: 1.0)
    view.colorPixelFormat = .bgra8Unorm
    view.depthStencilPixelFormat = .depth32Float
    view.preferredFramesPerSecond = 60

    let renderer = try Renderer(context: context)
    view.delegate = renderer

    let window = NSWindow(
        contentRect: view.frame,
        styleMask: [.titled, .closable, .resizable],
        backing: .buffered,
        defer: false)
    window.title = "PointCloudDemo — Milestone B"
    window.contentView = view
    window.center()
    window.makeKeyAndOrderFront(nil)
    app.activate(ignoringOtherApps: true)

    print("Rendering 1M points, orbiting, ~6s …")
    DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) {
        print("Done — rendered \(renderer.frames) frames, terminating cleanly.")
        NSApp.terminate(nil)
    }
    app.run()
} catch {
    print("PointCloudDemo failed: \(error)")
    exit(1)
}
