import AppKit
import MetalCore
import MetalKit
import QuartzCore

// MetalCoreDemo — hosts an MTKView in an AppKit window, clears every frame to the
// ROS2 Studio dark-theme background, and prints the frame interval. Proves the
// shared MetalContext drives a stable render loop end to end.
//
// 120fps on ProMotion is PENDING-AS (Apple-Silicon verification); on Intel this
// confirms correctness + a stable, leak-free loop. Auto-terminates after ~3s so
// it can run unattended in CI; close the window to quit early.

final class Renderer: NSObject, MTKViewDelegate {
    private let context: MetalContext
    private var frameCount = 0
    private var lastTimestamp = CACurrentMediaTime()
    private var intervalSum = 0.0

    init(context: MetalContext) {
        self.context = context
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let passDescriptor = view.currentRenderPassDescriptor,
              let commandBuffer = context.commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor)
        else { return }

        // Clearing happens via the pass's loadAction(.clear) + clearColor; an empty
        // encoder is enough to prove the loop. Real geometry lands in M5+.
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()

        let now = CACurrentMediaTime()
        intervalSum += now - lastTimestamp
        lastTimestamp = now
        frameCount += 1
        if frameCount % 60 == 0 {
            let avgMs = (intervalSum / Double(frameCount)) * 1000
            print("  rendered \(frameCount) frames  avg \(String(format: "%.2f", avgMs)) ms/frame")
        }
    }

    var frames: Int { frameCount }
}

do {
    let context = try MetalContext()
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)

    let view = MTKView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), device: context.device)
    view.clearColor = MTLClearColor(red: 0.05, green: 0.05, blue: 0.07, alpha: 1.0) // dark theme
    view.colorPixelFormat = .bgra8Unorm
    view.preferredFramesPerSecond = 60
    let renderer = Renderer(context: context)
    view.delegate = renderer

    let window = NSWindow(
        contentRect: view.frame,
        styleMask: [.titled, .closable, .resizable],
        backing: .buffered,
        defer: false
    )
    window.title = "MetalCoreDemo"
    window.contentView = view
    window.center()
    window.makeKeyAndOrderFront(nil)
    app.activate(ignoringOtherApps: true)

    print("MetalCoreDemo — device: \(context.device.name)")
    print("Clearing to dark theme at 60fps, auto-quits in ~3s …")
    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
        print("Done — rendered \(renderer.frames) frames, terminating cleanly.")
        NSApp.terminate(nil)
    }
    app.run()
} catch {
    print("MetalCoreDemo failed: \(error)")
    exit(1)
}
