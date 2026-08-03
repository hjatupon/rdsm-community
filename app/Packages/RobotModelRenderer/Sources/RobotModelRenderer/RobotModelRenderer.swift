import Foundation
import Logging
import Metal
import MetalCore
import MetalKit
import MeshLoader
import PointCloudRenderer
import simd

/// Uniform block shared with `PBR.metal`. Vectors are `float4` (xyz used) so the Swift
/// and Metal layouts match without float3 alignment surprises.
struct RobotUniforms {
    var mvp: simd_float4x4
    var model: simd_float4x4
    var albedo: SIMD4<Float>
    var lightDirection: SIMD4<Float>
    var cameraPosition: SIMD4<Float>
    var metallic: Float
    var roughness: Float
    var ambient: Float
    var pad: Float = 0
}

/// Caches the forward-kinematics solution and only recomputes when the joint state
/// (or model) changes — the contract's "FK cached, recomputed on state change".
final class FKCache {
    private(set) var solveCount = 0
    private var lastPositions: [String: Double]?
    private var cached: [String: simd_float4x4] = [:]

    func invalidate() {
        lastPositions = nil
        cached = [:]
    }

    func transforms(model: RobotModel, state: JointState, logger: any LoggerProtocol) -> [String: simd_float4x4] {
        if let lastPositions, lastPositions == state.positions { return cached }
        cached = ForwardKinematics.solve(model: model, state: state, logger: logger)
        lastPositions = state.positions
        solveCount += 1
        return cached
    }
}

/// Renders a robot's links with a Cook-Torrance PBR pipeline, posed by forward
/// kinematics from a ``JointState``. The renderer **never parses URDF** (Contract C7):
/// it consumes a ``RobotModel`` plus a `meshKey → MTKMesh` dictionary.
///
/// The Metal 4 PBR fast path is deferred (PENDING-AS); the pipeline here renders
/// correctly on macOS 15+ and Intel with a directional light over a dark studio bg.
public final class RobotModelRenderer {
    private let context: MetalContext
    private let logger: any LoggerProtocol
    private let pipeline: MTLRenderPipelineState
    private let depthState: MTLDepthStencilState

    private var model: RobotModel?
    private var meshes: [String: MTKMesh] = [:]
    /// Real meshes loaded via MeshLoader (stride 32, with texcoord). Takes precedence over `meshes`.
    private var loadedMeshes: [String: LoadedMesh] = [:]
    private var loadedMeshPipeline: MTLRenderPipelineState?
    private let cache = FKCache()

    private var camera = Camera()
    private var startTime = CACurrentMediaTime()
    /// When false, the camera no longer auto-orbits; user interactions / resets stick.
    public var autoOrbitEnabled = true
    /// Base transform from the fixed frame (e.g. "map") to the robot's root link.
    /// Applied before the ROS→Metal swizzle so the robot follows TF in the 3D scene.
    public var baseTransform: simd_float4x4 = .init(1)
    /// True when `setModel` has been called (model + meshes are loaded).
    public var isModelSet: Bool { model != nil }

    /// Overall opacity applied to every link (0 = invisible, 1 = opaque).
    public var overrideOpacity: Float = 1.0
    /// Link names that should be skipped during rendering.
    public var hiddenLinks: Set<String> = []
    /// Multiplicative tint applied to each link's base albedo color.
    public var tintColor: SIMD3<Float> = SIMD3<Float>(1, 1, 1)

    public init(context: MetalContext) throws {
        self.context = context
        logger = Logger(subsystem: "studio.ros2", category: "robotmodel")

        // Xcode app builds compile .metal → default.metallib inside Bundle.module.
        // SwiftPM test/CLI builds copy .metal verbatim and compile from source at runtime.
        let library: MTLLibrary
        if let lib = try? context.device.makeDefaultLibrary(bundle: Bundle.module) {
            library = lib
        } else if let url = Bundle.module.url(forResource: "PBR", withExtension: "metal") {
            do {
                let source = try String(contentsOf: url, encoding: .utf8)
                library = try context.device.makeLibrary(source: source, options: nil)
            } catch {
                throw MetalError.shaderCompilationFailed(error.localizedDescription)
            }
        } else {
            throw MetalError.libraryNotFound("PBR shaders not found in bundle")
        }
        guard let vertexFn = library.makeFunction(name: "pbrVertex"),
              let fragmentFn = library.makeFunction(name: "pbrFragment")
        else {
            throw MetalError.shaderCompilationFailed("pbrVertex/pbrFragment missing")
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFn
        descriptor.fragmentFunction = fragmentFn
        descriptor.vertexDescriptor = MTKMetalVertexDescriptorFromModelIO(Self.meshVertexDescriptor)
        let colorAtt = descriptor.colorAttachments[0]!
        colorAtt.pixelFormat = .bgra8Unorm
        colorAtt.isBlendingEnabled = true
        colorAtt.sourceRGBBlendFactor = .sourceAlpha
        colorAtt.destinationRGBBlendFactor = .oneMinusSourceAlpha
        colorAtt.rgbBlendOperation = .add
        colorAtt.sourceAlphaBlendFactor = .one
        colorAtt.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        descriptor.depthAttachmentPixelFormat = .depth32Float
        do {
            pipeline = try context.device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            throw MetalError.shaderCompilationFailed(error.localizedDescription)
        }

        let depthDescriptor = MTLDepthStencilDescriptor()
        depthDescriptor.depthCompareFunction = .less
        depthDescriptor.isDepthWriteEnabled = true
        guard let depthState = context.device.makeDepthStencilState(descriptor: depthDescriptor) else {
            throw MetalError.shaderCompilationFailed("depth-stencil state creation failed")
        }
        self.depthState = depthState
    }

    /// The vertex layout meshes passed to ``setModel(_:meshes:)`` must use: position
    /// `float3` at attribute 0, normal `float3` at attribute 1, interleaved in buffer 0.
    public static var meshVertexDescriptor: MDLVertexDescriptor {
        let descriptor = MDLVertexDescriptor()
        descriptor.attributes[0] = MDLVertexAttribute(
            name: MDLVertexAttributePosition, format: .float3, offset: 0, bufferIndex: 0)
        descriptor.attributes[1] = MDLVertexAttribute(
            name: MDLVertexAttributeNormal, format: .float3, offset: 12, bufferIndex: 0)
        descriptor.layouts[0] = MDLVertexBufferLayout(stride: 24)
        return descriptor
    }

    /// Vertex layout for `LoadedMesh` (stride 32: pos@0 / normal@12 / texcoord@24).
    /// The texcoord is unused by the PBR shader but present in the buffer.
    public static var loadedMeshVertexDescriptor: MDLVertexDescriptor {
        let descriptor = MDLVertexDescriptor()
        descriptor.attributes[0] = MDLVertexAttribute(
            name: MDLVertexAttributePosition, format: .float3, offset: 0, bufferIndex: 0)
        descriptor.attributes[1] = MDLVertexAttribute(
            name: MDLVertexAttributeNormal, format: .float3, offset: 12, bufferIndex: 0)
        descriptor.attributes[2] = MDLVertexAttribute(
            name: MDLVertexAttributeTextureCoordinate, format: .float2, offset: 24, bufferIndex: 0)
        descriptor.layouts[0] = MDLVertexBufferLayout(stride: 32)
        return descriptor
    }

    /// Resets the orbit camera back to its default position. Disables auto-orbit so
    /// the reset isn't immediately overwritten on the next frame.
    public func resetCamera() {
        camera = Camera()
        startTime = CACurrentMediaTime()
        autoOrbitEnabled = false
    }

    /// Installs a model and its meshes. Validates the kinematic tree and warns about
    /// (then skips) links whose `meshKey` has no matching mesh — rendering proceeds.
    public func setModel(_ model: RobotModel, meshes: [String: MTKMesh]) {
        self.model = model
        self.meshes = meshes
        self.loadedMeshes = [:]
        cache.invalidate()

        for link in ModelValidation.unreachableLinks(model: model) {
            logger.error("link unreachable from root", fields: [LogField(key: "link", value: link)])
        }
        if ModelValidation.hasCycle(model: model) {
            logger.error("kinematic tree contains a cycle")
        }
        for link in ModelValidation.skippedLinks(model: model, availableMeshKeys: Set(meshes.keys)) {
            logger.warning("no mesh for link; skipping", fields: [LogField(key: "link", value: link)])
        }
    }

    /// Installs a model with real `LoadedMesh` meshes loaded via MeshLoader.
    /// Uses a separate stride-32 pipeline. Builds the pipeline lazily on first call.
    public func setModel(_ model: RobotModel, loadedMeshes: [String: LoadedMesh]) {
        self.model = model
        self.loadedMeshes = loadedMeshes
        self.meshes = [:]
        cache.invalidate()
        if loadedMeshPipeline == nil {
            loadedMeshPipeline = try? makeLoadedMeshPipeline()
        }
    }

    /// Replace the mesh for a single link without reloading the whole model.
    /// Switches to the stride-32 loaded-mesh pipeline if not already active.
    public func overrideLinkMesh(meshKey: String, with mesh: LoadedMesh) {
        loadedMeshes[meshKey] = mesh
        meshes.removeValue(forKey: meshKey)
        if loadedMeshPipeline == nil {
            loadedMeshPipeline = try? makeLoadedMeshPipeline()
        }
    }

    private func makeLoadedMeshPipeline() throws -> MTLRenderPipelineState {
        // Same shader functions; only the vertex descriptor (stride 32 vs 24) differs.
        let library: MTLLibrary
        if let lib = try? context.device.makeDefaultLibrary(bundle: Bundle.module) {
            library = lib
        } else if let url = Bundle.module.url(forResource: "PBR", withExtension: "metal") {
            let source = try String(contentsOf: url, encoding: .utf8)
            library = try context.device.makeLibrary(source: source, options: nil)
        } else {
            throw MetalError.libraryNotFound("PBR shaders not found in bundle")
        }
        guard let vertexFn = library.makeFunction(name: "pbrVertex"),
              let fragmentFn = library.makeFunction(name: "pbrFragment")
        else {
            throw MetalError.shaderCompilationFailed("pbrVertex/pbrFragment missing")
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFn
        descriptor.fragmentFunction = fragmentFn
        descriptor.vertexDescriptor = MTKMetalVertexDescriptorFromModelIO(Self.loadedMeshVertexDescriptor)
        let lmColorAtt = descriptor.colorAttachments[0]!
        lmColorAtt.pixelFormat = .bgra8Unorm
        lmColorAtt.isBlendingEnabled = true
        lmColorAtt.sourceRGBBlendFactor = .sourceAlpha
        lmColorAtt.destinationRGBBlendFactor = .oneMinusSourceAlpha
        lmColorAtt.rgbBlendOperation = .add
        lmColorAtt.sourceAlphaBlendFactor = .one
        lmColorAtt.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        descriptor.depthAttachmentPixelFormat = .depth32Float
        return try context.device.makeRenderPipelineState(descriptor: descriptor)
    }

    /// Renders the posed model into `view`'s current pass. Render-thread only.
    public func render(state: JointState, view: MTKView, in cmd: MTLCommandBuffer) {
        guard let passDescriptor = view.currentRenderPassDescriptor,
              let encoder = cmd.makeRenderCommandEncoder(descriptor: passDescriptor)
        else { return }
        let size = view.drawableSize
        camera.aspect = size.height > 0 ? Float(size.width / size.height) : 1
        if autoOrbitEnabled {
            camera.azimuth = Float(CACurrentMediaTime() - startTime) * 0.4
        }
        let vp = camera.viewProjection
        let camPos = SIMD4<Float>(camera.position, 1)
        render(state: state, into: encoder, viewProjection: vp, cameraPosition: camPos, viewSize: size)
        encoder.endEncoding()
    }

    /// Same as `render(state:view:in:)` but accepts an external encoder and
    /// view-projection matrix. Does NOT endEncoding — the caller must do that.
    public func render(state: JointState, into encoder: MTLRenderCommandEncoder, viewProjection: simd_float4x4, cameraPosition: SIMD4<Float>, viewSize: CGSize) {
        guard let model else { return }
        let transforms = cache.transforms(model: model, state: state, logger: logger)

        let size = viewSize
        camera.aspect = size.height > 0 ? Float(size.width / size.height) : 1
        // Skip auto-orbit — the caller provides the view transform

        encoder.setDepthStencilState(depthState)
        encoder.setFrontFacing(.counterClockwise)
        encoder.setCullMode(.back)

        // Real loaded meshes (stride-32 pipeline) take precedence over MTKMesh box fallback.
        if !loadedMeshes.isEmpty, let loadedPipeline = loadedMeshPipeline {
            encoder.setRenderPipelineState(loadedPipeline)
            for link in model.links {
                guard !hiddenLinks.contains(link.name) else { continue }
                guard let key = link.meshKey, let mesh = loadedMeshes[key],
                      let world = transforms[link.name] else { continue }
                let scaleMatrix = simd_float4x4(diagonal: SIMD4<Float>(link.meshScale, 1))
                let metalWorld = rosToMetal * baseTransform * world * link.visualOrigin.matrix * scaleMatrix
                var uniforms = makeUniforms(
                    mvp: viewProjection * metalWorld,
                    world: metalWorld,
                    cameraPosition: cameraPosition,
                    material: mesh.submeshes.first?.material)
                encoder.setVertexBytes(&uniforms, length: MemoryLayout<RobotUniforms>.stride, index: 1)
                encoder.setFragmentBytes(&uniforms, length: MemoryLayout<RobotUniforms>.stride, index: 0)
                draw(loadedMesh: mesh, encoder: encoder)
            }
        } else {
            encoder.setRenderPipelineState(pipeline)
            for link in model.links {
                guard !hiddenLinks.contains(link.name) else { continue }
                guard let key = link.meshKey, let mesh = meshes[key],
                      let world = transforms[link.name] else { continue }
                let metalWorld = rosToMetal * baseTransform * world * link.visualOrigin.matrix
                var uniforms = makeUniforms(
                    mvp: viewProjection * metalWorld,
                    world: metalWorld,
                    cameraPosition: cameraPosition,
                    material: nil)
                encoder.setVertexBytes(&uniforms, length: MemoryLayout<RobotUniforms>.stride, index: 1)
                encoder.setFragmentBytes(&uniforms, length: MemoryLayout<RobotUniforms>.stride, index: 0)
                draw(mesh: mesh, encoder: encoder)
            }
        }
    }

    private func makeUniforms(
        mvp: simd_float4x4,
        world: simd_float4x4,
        cameraPosition: SIMD4<Float>,
        material: Material?
    ) -> RobotUniforms {
        let base = material?.baseColor ?? SIMD4<Float>(0.62, 0.64, 0.67, 1)
        let albedo = SIMD4<Float>(base.x * tintColor.x, base.y * tintColor.y, base.z * tintColor.z, overrideOpacity)
        let metallic = material?.metallic ?? 0.55
        let roughness = material?.roughness ?? 0.45
        return RobotUniforms(
            mvp: mvp,
            model: world,
            albedo: albedo,
            lightDirection: SIMD4<Float>(normalize(SIMD3<Float>(0.4, -1, 0.3)), 0),
            cameraPosition: cameraPosition,
            metallic: metallic,
            roughness: roughness,
            ambient: 0.08)
    }

    private func draw(mesh: MTKMesh, encoder: MTLRenderCommandEncoder) {
        for (index, vertexBuffer) in mesh.vertexBuffers.enumerated() {
            encoder.setVertexBuffer(vertexBuffer.buffer, offset: vertexBuffer.offset, index: index)
        }
        for submesh in mesh.submeshes {
            encoder.drawIndexedPrimitives(
                type: submesh.primitiveType,
                indexCount: submesh.indexCount,
                indexType: submesh.indexType,
                indexBuffer: submesh.indexBuffer.buffer,
                indexBufferOffset: submesh.indexBuffer.offset)
        }
    }

    private func draw(loadedMesh: LoadedMesh, encoder: MTLRenderCommandEncoder) {
        encoder.setVertexBuffer(loadedMesh.vertexBuffer, offset: 0, index: 0)
        for submesh in loadedMesh.submeshes {
            encoder.drawIndexedPrimitives(
                type: submesh.primitiveType,
                indexCount: submesh.indexCount,
                indexType: submesh.indexType,
                indexBuffer: submesh.indexBuffer,
                indexBufferOffset: 0)
        }
    }
}
