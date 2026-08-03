import simd
import Foundation

/// Orbit-camera parameters for the 3D viewer.
///
/// Pure value type — no Metal dependency, fully unit-testable. Azimuth and
/// elevation are in radians. The view matrix is right-handed, Y-up.
public struct CameraState: Sendable, Equatable {
    /// Rotation around the world Y axis (yaw), in radians.
    public var azimuth: Float
    /// Elevation above the horizon, in radians. Clamped to (-π/2, π/2).
    public var elevation: Float
    /// Distance from `target` to the camera eye. Always > 0.
    public var distance: Float
    /// World-space look-at point.
    public var target: SIMD3<Float>

    public static let `default` = CameraState(
        azimuth: 0.5, elevation: 0.4, distance: 5.0, target: .zero)

    public init(
        azimuth: Float = 0.5,
        elevation: Float = 0.4,
        distance: Float = 5.0,
        target: SIMD3<Float> = .zero
    ) {
        self.azimuth = azimuth
        self.elevation = Swift.max(-.pi / 2 + 0.01, Swift.min(.pi / 2 - 0.01, elevation))
        self.distance = Swift.max(0.05, distance)
        self.target = target
    }

    // MARK: - Derived geometry

    /// World-space camera eye position.
    public var position: SIMD3<Float> {
        let cosEl = cos(elevation)
        return target + SIMD3(
            distance * cosEl * sin(azimuth),
            distance * sin(elevation),
            distance * cosEl * cos(azimuth))
    }

    /// Right-handed look-at view matrix.
    public var viewMatrix: simd_float4x4 {
        let eye = position
        let f = normalize(target - eye)        // forward
        let r = normalize(cross(f, SIMD3<Float>(0, 1, 0)))  // right
        let u = cross(r, f)                    // up

        return simd_float4x4(rows: [
            SIMD4(r.x,  r.y,  r.z,  -dot(r, eye)),
            SIMD4(u.x,  u.y,  u.z,  -dot(u, eye)),
            SIMD4(-f.x, -f.y, -f.z,  dot(f, eye)),
            SIMD4(0,    0,    0,    1),
        ])
    }

    /// Symmetric perspective projection matrix (Metal NDC, reverse-Z not used here).
    public func projectionMatrix(
        aspect: Float,
        fovY: Float = .pi / 3,
        near: Float = 0.05,
        far: Float = 1_000
    ) -> simd_float4x4 {
        let f = 1 / tan(fovY / 2)
        let q = far / (near - far)
        return simd_float4x4(rows: [
            SIMD4(f / aspect, 0,  0,      0),
            SIMD4(0,          f,  0,      0),
            SIMD4(0,          0,  q,      q * near),
            SIMD4(0,          0, -1,      0),
        ])
    }

    /// Combined view-projection matrix at the given aspect ratio.
    public func viewProjection(aspect: Float) -> simd_float4x4 {
        projectionMatrix(aspect: aspect) * viewMatrix
    }

    // MARK: - Interaction helpers

    /// Returns a new state with azimuth and elevation shifted by drag deltas (pixels).
    public func orbited(deltaX: Float, deltaY: Float, sensitivity: Float = 0.005) -> CameraState {
        CameraState(
            azimuth: azimuth - deltaX * sensitivity,
            elevation: elevation + deltaY * sensitivity,
            distance: distance,
            target: target)
    }

    /// Returns a new state with distance scaled by a scroll factor (> 1 = zoom in).
    public func zoomed(factor: Float) -> CameraState {
        CameraState(
            azimuth: azimuth,
            elevation: elevation,
            distance: distance / Swift.max(0.01, factor),
            target: target)
    }
}
