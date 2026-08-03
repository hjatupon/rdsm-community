import Testing
import simd
@testable import PointCloudRenderer

@Test func swizzlePosition() {
    let (x, y, z) = swizzle(1, 2, 3)
    #expect(x == -2)  // -ROS_y
    #expect(y == 3)   //  ROS_z
    #expect(z == 1)   //  ROS_x
}

@Test func swizzleCardinalAxes() {
    #expect(swizzle(1, 0, 0) == (0, 0, 1))  // ROS X → Metal Z
    #expect(swizzle(0, 1, 0) == (-1, 0, 0)) // ROS Y → Metal -X
    #expect(swizzle(0, 0, 1) == (0, 1, 0))  // ROS Z → Metal Y
}

@Test func swizzleNegatives() {
    #expect(swizzle(-1, 0, 0) == (0, 0, -1))
    #expect(swizzle(0, -1, 0) == (1, 0, 0))
    #expect(swizzle(0, 0, -1) == (0, -1, 0))
}

@Test func swizzleQuaternion() {
    let q = simd_quatd(ix: 1, iy: 2, iz: 3, r: 0)
    let r = swizzleQuat(q)
    #expect(r.vector.x == -2)  // -ROS_qy
    #expect(r.vector.y == 3)   //  ROS_qz
    #expect(r.vector.z == 1)   //  ROS_qx
    #expect(r.vector.w == 0)   //  ROS_qw
}

@Test func rosToMetalMatrix() {
    let rosVec = SIMD4<Float>(1, 2, 3, 1)
    let metalVec = rosToMetal * rosVec
    #expect(metalVec.x == -2)  // -ROS_y
    #expect(metalVec.y == 3)   //  ROS_z
    #expect(metalVec.z == 1)   //  ROS_x
}

// MARK: - Reverse swizzle

@Test func reverseSwizzleCardinal() {
    let (rosX, rosY) = reverseSwizzle(metalX: 0, metalZ: 1)
    #expect(rosX == 1)   // Metal Z → ROS X
    #expect(rosY == 0)   // -Metal X → ROS Y
}

@Test func reverseSwizzleNegative() {
    let (rosX, rosY) = reverseSwizzle(metalX: -2, metalZ: 5)
    #expect(rosX == 5)    // Metal Z
    #expect(rosY == 2)    // -(-Metal X)
}

@Test func reverseSwizzleRoundtrip() {
    let rosX: Float = 3; let rosY: Float = 4; let rosZ: Float = 5
    let (mx, my, mz) = swizzle(rosX, rosY, rosZ)
    // Only ground-plane components (X, Z) survive the roundtrip
    let (roundX, roundY) = reverseSwizzle(metalX: mx, metalZ: mz)
    #expect(roundX == Double(rosX))
    #expect(roundY == Double(rosY))
}

// MARK: - Yaw extraction

@Test func rosYawIdentity() {
    let yaw = rosYaw(from: (0, 0, 0, 1))  // identity quaternion
    #expect(yaw == 0)
}

@Test func rosYawQuarterTurn() {
    // 90° around Z: q = (0, 0, sin(π/4), cos(π/4))
    let yaw = rosYaw(from: (0, 0, sin(.pi / 4), cos(.pi / 4)))
    #expect(abs(yaw - .pi / 2) < 1e-6)
}

// MARK: - Pattern A (reference note)
//
// The codebase uses "Pattern A" throughout: rotate in ROS space, then swizzle.
//   let world = rosQuat.act(rosPoint)        // rotate in ROS space
//   let (mx, my, mz) = swizzle(Float(world)) // then swizzle
//
// swizzleQuat exists as a documentation of the quaternion swizzle formula but
// is NOT the runtime reverse of swizzle(). Pattern A is the architecturally
// correct approach and is proven by all 10+ message handlers working correctly.
