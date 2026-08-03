import simd

/// A rigid-body transform in double precision, matching tf2's frame convention.
///
/// Uses `Double` throughout — never `Float` — to maintain tf2-reference accuracy
/// (Contract C4 tolerance: ≤1e-6 m translation, ≤1e-7 rad rotation error).
public struct TFTransform: Sendable, Hashable {
    public var translation: SIMD3<Double>
    public var rotation: simd_quatd

    public static let identity = TFTransform(
        translation: .zero,
        rotation: simd_quatd(ix: 0, iy: 0, iz: 0, r: 1))

    public init(translation: SIMD3<Double>, rotation: simd_quatd) {
        self.translation = translation
        self.rotation = rotation.normalized
    }

    // MARK: - Composition

    /// Applies `self` then `other` (i.e. `other * self` in matrix terms).
    public func then(_ other: TFTransform) -> TFTransform {
        let rot = other.rotation.act(translation) + other.translation
        return TFTransform(
            translation: rot,
            rotation: other.rotation * self.rotation)
    }

    /// Returns the inverse transform.
    public var inverse: TFTransform {
        let invRot = rotation.inverse
        return TFTransform(
            translation: invRot.act(-translation),
            rotation: invRot)
    }

    // MARK: - Hashable

    public static func == (lhs: TFTransform, rhs: TFTransform) -> Bool {
        lhs.translation == rhs.translation &&
        lhs.rotation.vector == rhs.rotation.vector
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(translation.x)
        hasher.combine(translation.y)
        hasher.combine(translation.z)
        hasher.combine(rotation.vector.x)
        hasher.combine(rotation.vector.y)
        hasher.combine(rotation.vector.z)
        hasher.combine(rotation.vector.w)
    }
}

// MARK: - simd_quatd normalize

private extension simd_quatd {
    var normalized: simd_quatd { simd_normalize(self) }
}
