import simd

// ---------------------------------------------------------------------------
// Coordinate swizzle helpers
//
// ROS2 Studio bridges two incompatible coordinate conventions:
//
//   | Convention | Forward | Left  | Up  |
//   |------------|---------|-------|-----|
//   | ROS (REP)  | X       | Y     | Z   |
//   | Metal (3D) | Z       | -X    | Y   |
//
// The fundamental swizzle is:
//
//   Metal(x, y, z) = (-ROS_y, ROS_z, ROS_x)
//
// All ROS data arriving via rosbridge is swizzled once on ingestion.
// Renderers and interaction code operate exclusively in Metal Y-up
// coordinates thereafter.
// ---------------------------------------------------------------------------

/// Swizzle a position from ROS Z-up (x-forward, y-left, z-up) to Metal Y-up.
///
/// ```
/// Metal(x, y, z) = (-ROS_y, ROS_z, ROS_x)
/// ```
@inlinable
public func swizzle(_ x: Float, _ y: Float, _ z: Float) -> (Float, Float, Float) {
    (-y, z, x)
}

/// Swizzle a ROS Z-up quaternion to Metal Y-up.
///
/// ```
/// Metal q = simd_quatd(ix: -ROS_qy, iy: ROS_qz, iz: ROS_qx, r: ROS_qw)
/// ```
@inlinable
public func swizzleQuat(_ q: simd_quatd) -> simd_quatd {
    simd_quatd(ix: -q.vector.y, iy: q.vector.z, iz: q.vector.x, r: q.vector.w)
}

/// 4×4 matrix converting ROS Z-up → Metal Y-up.
///
/// When acting on column vectors `(ROS_x, ROS_y, ROS_z, 1)`:
///
/// ```
/// | Metal_x |   |  0 -1  0  0 |   | ROS_x |
/// | Metal_y | = |  0  0  1  0 | * | ROS_y |
/// | Metal_z |   |  1  0  0  0 |   | ROS_z |
/// |    1    |   |  0  0  0  1 |   |   1   |
/// ```
///
/// Which expands to:
/// ```
/// Metal_x = -ROS_y
/// Metal_y =  ROS_z
/// Metal_z =  ROS_x
/// ```
public let rosToMetal = simd_float4x4(columns: (
    SIMD4<Float>( 0,  0,  1,  0),
    SIMD4<Float>(-1,  0,  0,  0),
    SIMD4<Float>( 0,  1,  0,  0),
    SIMD4<Float>( 0,  0,  0,  1)
))

// ---------------------------------------------------------------------------
// Reverse swizzle (Metal → ROS, for publishing back to ROS)
// ---------------------------------------------------------------------------

/// Reverse-swizzle a Metal Y-up position back to ROS Z-up.
///
/// The inverse of `Metal(x, y, z) = (-ROS_y, ROS_z, ROS_x)` is:
///
/// ```
/// ROS_x =  Metal_z
/// ROS_y = -Metal_x
/// ROS_z =  Metal_y
/// ```
///
/// - Parameters:
///   - x: Metal X coordinate (right).
///   - z: Metal Z coordinate (forward).
/// - Returns: ROS `(forward, left)` — i.e. ROS X (forward) and ROS Y (left).
///   ROS Z (up) is always 0 because the caller is operating on the ground plane.
@inlinable
public func reverseSwizzle(metalX x: Float, metalZ z: Float) -> (rosX: Double, rosY: Double) {
    (Double(z), Double(-x))
}

// ---------------------------------------------------------------------------
// Yaw extraction from a ROS quaternion
// ---------------------------------------------------------------------------

/// Extract the yaw angle (rotation around ROS Z-up) from a ROS-frame quaternion.
///
/// This is the standard ROS formula:
/// ```
/// yaw = atan2(2*(qw*qz + qx*qy), 1 - 2*(qy² + qz²))
/// ```
///
/// The quaternion MUST be in **ROS convention** (x-forward, y-left, z-up).
/// The returned yaw is in **ROS convention** (rotation around ROS Z-up)
/// and can be used directly to compute a forward direction vector
/// via `(cos(yaw), sin(yaw))`.
@inlinable
public func rosYaw(from q: (x: Double, y: Double, z: Double, w: Double)) -> Double {
    atan2(2 * (q.w * q.z + q.x * q.y), 1 - 2 * (q.y * q.y + q.z * q.z))
}

// ---------------------------------------------------------------------------
// Pattern reference
//
// The codebase uses Pattern A throughout — it is the single correct approach:
//
//   let world = rosQuat.act(rosPoint)     // rotate in ROS space
//   let (mx, my, mz) = swizzle(world)     // then swizzle
//
// swizzleQuat exists to document the quaternion-component mapping formula.
// It is NOT the runtime inverse of swizzle() — the two patterns involve
// different quaternion-conjugation conventions in simd. All 10+ message
// handlers use Pattern A and produce correct Metal-space coordinates.
//
// Pattern A is preferred because:
// - It keeps the TF transform in its natural ROS coordinate frame.
// - The swizzle happens once at the end as a simple negation/permutation.
// - It avoids the subtle sign conventions of quaternion swizzling.
// ---------------------------------------------------------------------------
