import AppKit
import Metal
import MetalCore
import MetalKit
import RobotModelRenderer
import simd

// RobotModelDemo — a 3-joint articulated arm built directly as a RobotModel (no URDF
// parsing: Contract C7), each link a box MTKMesh, posed by forward kinematics. A
// per-revolute-joint slider drives the JointState; the arm also auto-sweeps so an
// unattended run shows motion. 60fps PBR is PENDING-AS (Apple-Silicon sign-off);
// Intel verifies correctness, FK, depth, and the dark studio look.

let linkLength: Float = 0.5
let jointNames = ["j1", "j2", "j3"]

func makeModel() -> RobotModel {
    let links = [
        Link(name: "base", meshKey: "segment"),
        Link(name: "link1", meshKey: "segment"),
        Link(name: "link2", meshKey: "segment"),
        Link(name: "link3", meshKey: "segment"),
    ]
    let origin = Transform(translation: SIMD3(0, linkLength, 0))
    let joints = [
        Joint(name: "j1", parent: "base", child: "link1", type: .revolute, axis: SIMD3(0, 0, 1), origin: origin),
        Joint(name: "j2", parent: "link1", child: "link2", type: .revolute, axis: SIMD3(0, 0, 1), origin: origin),
        Joint(name: "j3", parent: "link2", child: "link3", type: .revolute, axis: SIMD3(1, 0, 0), origin: origin),
    ]
    return RobotModel(links: links, joints: joints, rootLink: "base")
}

func makeSegmentMesh(device: MTLDevice) throws -> MTKMesh {
    let allocator = MTKMeshBufferAllocator(device: device)
    let mdlMesh = MDLMesh(
        boxWithExtent: SIMD3(0.18, linkLength * 0.9, 0.18),
        segments: SIMD3(1, 1, 1),
        inwardNormals: false,
        geometryType: .triangles,
        allocator: allocator)
    mdlMesh.vertexDescriptor = RobotModelRenderer.meshVertexDescriptor
    return try MTKMesh(mesh: mdlMesh, device: device)
}

final class JointStore: @unchecked Sendable {
    private let lock = NSLock()
    private var positions: [String: Double] = [:]
    func set(_ name: String, _ value: Double) { lock.withLock { positions[name] = value } }
    func state() -> JointState { lock.withLock { JointState(positions: positions) } }
}

final class Renderer: NSObject, MTKViewDelegate {
    private let context: MetalContext
    private let robot: RobotModelRenderer
    private let store: JointStore
    private var frameCount = 0

    init(context: MetalContext, store: JointStore) throws {
        self.context = context
        self.store = store
        robot = try RobotModelRenderer(context: context)
        super.init()
        let mesh = try makeSegmentMesh(device: context.device)
        robot.setModel(makeModel(), meshes: ["segment": mesh])
        print("RobotModelDemo — 4-link arm, 3 revolute joints; sliders drive JointState")
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let commandBuffer = context.commandQueue.makeCommandBuffer() else { return }
        robot.render(state: store.state(), view: view, in: commandBuffer)
        if let drawable = view.currentDrawable { commandBuffer.present(drawable) }
        commandBuffer.commit()
        frameCount += 1
        if frameCount % 60 == 0 { print("  rendered \(frameCount) frames") }
    }

    var frames: Int { frameCount }
}

final class Controller: NSObject {
    let store: JointStore
    var sliders: [NSSlider] = []

    init(store: JointStore) { self.store = store }

    @objc func sliderMoved(_ sender: NSSlider) {
        store.set(jointNames[sender.tag], sender.doubleValue)
    }

    // Auto-sweep so the unattended run shows the joints moving via the slider path.
    @objc func tick() {
        let t = CACurrentMediaTime()
        for (i, slider) in sliders.enumerated() {
            let value = sin(t * 1.2 + Double(i)) * 0.7
            slider.doubleValue = value
            store.set(jointNames[i], value)
        }
    }
}

do {
    let context = try MetalContext()
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)

    let store = JointStore()
    let controller = Controller(store: store)

    let mtkView = MTKView(frame: NSRect(x: 0, y: 0, width: 760, height: 700), device: context.device)
    mtkView.clearColor = MTLClearColor(red: 0.05, green: 0.05, blue: 0.07, alpha: 1.0)
    mtkView.colorPixelFormat = .bgra8Unorm
    mtkView.depthStencilPixelFormat = .depth32Float
    mtkView.preferredFramesPerSecond = 60
    let renderer = try Renderer(context: context, store: store)
    mtkView.delegate = renderer

    // Slider column for the three revolute joints.
    let stack = NSStackView(frame: NSRect(x: 0, y: 0, width: 200, height: 700))
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.edgeInsets = NSEdgeInsets(top: 20, left: 12, bottom: 20, right: 12)
    for (i, name) in jointNames.enumerated() {
        let label = NSTextField(labelWithString: "\(name) (rad)")
        let slider = NSSlider(value: 0, minValue: -1.4, maxValue: 1.4, target: controller, action: #selector(Controller.sliderMoved(_:)))
        slider.tag = i
        controller.sliders.append(slider)
        stack.addArrangedSubview(label)
        stack.addArrangedSubview(slider)
        slider.widthAnchor.constraint(equalToConstant: 170).isActive = true
    }

    let split = NSStackView(frame: NSRect(x: 0, y: 0, width: 960, height: 700))
    split.orientation = .horizontal
    split.addArrangedSubview(stack)
    split.addArrangedSubview(mtkView)

    let window = NSWindow(
        contentRect: split.frame,
        styleMask: [.titled, .closable, .resizable],
        backing: .buffered,
        defer: false)
    window.title = "RobotModelDemo"
    window.contentView = split
    window.center()
    window.makeKeyAndOrderFront(nil)
    app.activate(ignoringOtherApps: true)

    let timer = Timer.scheduledTimer(
        timeInterval: 1.0 / 60.0, target: controller, selector: #selector(Controller.tick), userInfo: nil, repeats: true)
    RunLoop.main.add(timer, forMode: .common)

    print("Rendering robot, auto-sweeping joints, ~6s …")
    DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) {
        timer.invalidate()
        print("Done — rendered \(renderer.frames) frames, terminating cleanly.")
        NSApp.terminate(nil)
    }
    app.run()
} catch {
    print("RobotModelDemo failed: \(error)")
    exit(1)
}
