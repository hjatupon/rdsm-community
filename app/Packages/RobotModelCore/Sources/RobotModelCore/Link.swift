import simd

/// A rigid body in the robot. `meshKey` selects the visual mesh supplied to the
/// renderer; a `nil` key means the link has no visual (e.g. a pure kinematic frame)
/// and is skipped at render time.
public struct Link: Sendable, Hashable {
    public let name: String
    public let meshKey: String?
    /// URDF `<mesh scale="x y z"/>` — converts mesh-file units (often mm) to metres.
    public let meshScale: SIMD3<Float>
    /// URDF `<visual><origin xyz="..." rpy="..."/>` — offset from the joint origin to
    /// where the mesh is placed. Applied between FK and scale in the render chain.
    public let visualOrigin: Transform

    public init(
        name: String,
        meshKey: String?,
        meshScale: SIMD3<Float> = SIMD3(1, 1, 1),
        visualOrigin: Transform = .identity
    ) {
        self.name = name
        self.meshKey = meshKey
        self.meshScale = meshScale
        self.visualOrigin = visualOrigin
    }
}
