import simd

/// A rigid transform — translation plus a unit-quaternion rotation. It is the
/// joint-origin and link-pose primitive; ``matrix`` materializes the 4×4 form used by
/// forward kinematics and rendering.
///
/// Uses `Float` precision throughout for rendering compatibility with Metal shaders.
/// The separate `TFTree.Transform` uses `Double` precision for interpolation accuracy.
///
/// `Hashable` over its components so ``Joint`` can be `Hashable`, since `simd_quatf`
/// is not `Hashable` on its own.
public struct Transform: Sendable, Hashable {
    public var translation: SIMD3<Float>
    public var rotation: simd_quatf

    public init(
        translation: SIMD3<Float> = .zero,
        rotation: simd_quatf = simd_quatf(vector: SIMD4<Float>(0, 0, 0, 1)))
    {
        self.translation = translation
        self.rotation = rotation
    }

    public static let identity = Transform()

    /// The combined rotation-then-translation as a column-major 4×4 matrix.
    public var matrix: simd_float4x4 {
        var m = simd_float4x4(rotation)
        m.columns.3 = SIMD4<Float>(translation, 1)
        return m
    }

    public static func == (lhs: Transform, rhs: Transform) -> Bool {
        lhs.translation == rhs.translation && lhs.rotation.vector == rhs.rotation.vector
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(translation)
        hasher.combine(rotation.vector)
    }
}
