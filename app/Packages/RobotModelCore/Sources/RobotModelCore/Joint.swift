import simd

/// The kinematic relationship of a joint, mirroring URDF joint types.
public enum JointType: Sendable, Hashable {
    case fixed, revolute, prismatic, continuous, floating, planar
}

/// Connects `parent` → `child` with a motion of `type` about/along `axis`, offset by
/// `origin` (the child frame relative to the parent at zero joint position).
public struct Joint: Sendable, Hashable {
    public let name: String
    public let parent: String
    public let child: String
    public let type: JointType
    public let axis: SIMD3<Float>
    public let origin: Transform

    public init(
        name: String,
        parent: String,
        child: String,
        type: JointType,
        axis: SIMD3<Float>,
        origin: Transform)
    {
        self.name = name
        self.parent = parent
        self.child = child
        self.type = type
        self.axis = axis
        self.origin = origin
    }
}
