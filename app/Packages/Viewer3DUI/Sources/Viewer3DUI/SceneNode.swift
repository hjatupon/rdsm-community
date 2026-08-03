import simd

/// A node in the 3D scene graph, keyed by TF frame name.
///
/// Each node holds a local transform relative to its parent frame.
/// World transforms are computed recursively by composing parent × local.
/// This is a pure value type — no Metal, fully unit-testable.
public struct SceneNode: Sendable, Identifiable {
    /// TF frame name, used as the unique identifier within a scene.
    public let id: String
    /// Transform from this node's parent frame into this node's frame.
    public var localTransform: simd_float4x4
    /// Child nodes whose local transforms are relative to this node.
    public var children: [SceneNode]

    public init(
        id: String,
        localTransform: simd_float4x4 = matrix_identity_float4x4,
        children: [SceneNode] = []
    ) {
        self.id = id
        self.localTransform = localTransform
        self.children = children
    }

    // MARK: - Transform composition

    /// World transform of this node given the accumulated parent world transform.
    public func worldTransform(
        parentWorld: simd_float4x4 = matrix_identity_float4x4
    ) -> simd_float4x4 {
        parentWorld * localTransform
    }

    /// Collects all `(frameID → worldTransform)` pairs for this node and every
    /// descendant. Later entries overwrite earlier ones if IDs collide.
    public func allWorldTransforms(
        parentWorld: simd_float4x4 = matrix_identity_float4x4
    ) -> [String: simd_float4x4] {
        let world = parentWorld * localTransform
        var result: [String: simd_float4x4] = [id: world]
        for child in children {
            result.merge(child.allWorldTransforms(parentWorld: world)) { _, new in new }
        }
        return result
    }
}
