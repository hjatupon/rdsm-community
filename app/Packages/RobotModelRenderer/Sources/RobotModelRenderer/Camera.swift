import simd

/// Internal orbit camera (value type) producing view/projection matrices. The renderer
/// owns one and auto-orbits it so the locked render API needs no camera parameter.
struct Camera {
    var distance: Float = 3
    var azimuth: Float = 0
    var elevation: Float = 0.4
    var target = SIMD3<Float>(0, 0.3, 0)
    var fovY: Float = 1.0472 // 60°
    var aspect: Float = 1
    var near: Float = 0.02
    var far: Float = 100

    var position: SIMD3<Float> {
        let x = distance * cos(elevation) * sin(azimuth)
        let y = distance * sin(elevation)
        let z = distance * cos(elevation) * cos(azimuth)
        return target + SIMD3(x, y, z)
    }

    var viewProjection: simd_float4x4 {
        projection * view
    }

    var view: simd_float4x4 {
        Self.lookAt(eye: position, center: target, up: SIMD3(0, 1, 0))
    }

    var projection: simd_float4x4 {
        Self.perspective(fovY: fovY, aspect: aspect, near: near, far: far)
    }

    static func lookAt(eye: SIMD3<Float>, center: SIMD3<Float>, up: SIMD3<Float>) -> simd_float4x4 {
        let f = normalize(center - eye)
        let s = normalize(cross(f, up))
        let u = cross(s, f)
        return simd_float4x4(
            SIMD4(s.x, u.x, -f.x, 0),
            SIMD4(s.y, u.y, -f.y, 0),
            SIMD4(s.z, u.z, -f.z, 0),
            SIMD4(-dot(s, eye), -dot(u, eye), dot(f, eye), 1))
    }

    /// Right-handed perspective with Metal's [0, 1] clip-space depth.
    static func perspective(fovY: Float, aspect: Float, near: Float, far: Float) -> simd_float4x4 {
        let y = 1 / tan(fovY * 0.5)
        let x = y / aspect
        let z = far / (near - far)
        return simd_float4x4(
            SIMD4(x, 0, 0, 0),
            SIMD4(0, y, 0, 0),
            SIMD4(0, 0, z, -1),
            SIMD4(0, 0, z * near, 0))
    }
}
