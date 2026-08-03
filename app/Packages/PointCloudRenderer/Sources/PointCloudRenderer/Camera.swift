import simd

/// A minimal orbit camera (value type) producing a view-projection matrix. Internal
/// to the package: ``PointCloudRenderer`` owns one and auto-orbits it each frame so
/// the demo shows the cloud from all sides without the locked render API needing a
/// camera parameter.
///
/// SolidWorks-style orbit: `target` is always fixed at the world origin (0, 0, 0)
/// and is the immutable orbit pivot. `panOffset` accumulates screen-space pan
/// translations, moving the entire camera system (eye + look-at point) together
/// without ever drifting the orbit pivot. Orbit/yaw/pitch/roll always circle the
/// world origin — data moves through the frame, the pivot stays fixed.
struct Camera: Codable {
    var distance: Float = 4
    var azimuth: Float = 0
    var elevation: Float = 0.45
    /// Roll around the view-forward axis, in radians. Defaults to 0 (no bank).
    var roll: Float = 0
    /// Orbit pivot — always world origin. Do NOT modify this for pan; use `panOffset`.
    var target = SIMD3<Float>(0, 0, 0)
    /// Screen-space pan offset applied to both eye and look-at point together.
    /// Accumulates pan gestures without drifting the orbit pivot.
    var panOffset = SIMD3<Float>(0, 0, 0)
    var fovY: Float = 1.0472 // 60°
    var aspect: Float = 1
    var near: Float = 0.05
    var far: Float = 500

    // MARK: - Codable support for SIMD3<Float>
    enum CodingKeys: String, CodingKey {
        case distance, azimuth, elevation, roll
        case targetX, targetY, targetZ
        case panOffsetX, panOffsetY, panOffsetZ
        case fovY, aspect, near, far
    }

    init(distance: Float = 4, azimuth: Float = 0, elevation: Float = 0.45,
         roll: Float = 0,
         target: SIMD3<Float> = .zero,
         panOffset: SIMD3<Float> = .zero,
         fovY: Float = 1.0472,
         aspect: Float = 1, near: Float = 0.05, far: Float = 500) {
        self.distance = distance
        self.azimuth = azimuth
        self.elevation = elevation
        self.roll = roll
        self.target = target
        self.panOffset = panOffset
        self.fovY = fovY
        self.aspect = aspect
        self.near = near
        self.far = far
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        distance  = try c.decode(Float.self, forKey: .distance)
        azimuth   = try c.decode(Float.self, forKey: .azimuth)
        elevation = try c.decode(Float.self, forKey: .elevation)
        // roll is new — use decodeIfPresent so old persisted state decodes cleanly
        roll      = (try? c.decodeIfPresent(Float.self, forKey: .roll)) ?? 0
        // target: decode if present, default to zero (orbit pivot is world origin)
        let tx    = (try? c.decodeIfPresent(Float.self, forKey: .targetX)) ?? 0
        let ty    = (try? c.decodeIfPresent(Float.self, forKey: .targetY)) ?? 0
        let tz    = (try? c.decodeIfPresent(Float.self, forKey: .targetZ)) ?? 0
        target    = SIMD3(tx, ty, tz)
        // panOffset: new field — use decodeIfPresent so old persisted state decodes cleanly
        let px    = (try? c.decodeIfPresent(Float.self, forKey: .panOffsetX)) ?? 0
        let py    = (try? c.decodeIfPresent(Float.self, forKey: .panOffsetY)) ?? 0
        let pz    = (try? c.decodeIfPresent(Float.self, forKey: .panOffsetZ)) ?? 0
        panOffset = SIMD3(px, py, pz)
        fovY      = try c.decode(Float.self, forKey: .fovY)
        aspect    = try c.decode(Float.self, forKey: .aspect)
        near      = try c.decode(Float.self, forKey: .near)
        far       = try c.decode(Float.self, forKey: .far)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(distance,    forKey: .distance)
        try c.encode(azimuth,     forKey: .azimuth)
        try c.encode(elevation,   forKey: .elevation)
        try c.encode(roll,        forKey: .roll)
        try c.encode(target.x,    forKey: .targetX)
        try c.encode(target.y,    forKey: .targetY)
        try c.encode(target.z,    forKey: .targetZ)
        try c.encode(panOffset.x, forKey: .panOffsetX)
        try c.encode(panOffset.y, forKey: .panOffsetY)
        try c.encode(panOffset.z, forKey: .panOffsetZ)
        try c.encode(fovY,        forKey: .fovY)
        try c.encode(aspect,      forKey: .aspect)
        try c.encode(near,        forKey: .near)
        try c.encode(far,         forKey: .far)
    }

    /// World-space camera eye position (orbit around target, then shift by panOffset).
    var position: SIMD3<Float> {
        let x = distance * cos(elevation) * sin(azimuth)
        let y = distance * sin(elevation)
        let z = distance * cos(elevation) * cos(azimuth)
        // Orbit around `target` (world origin), then translate by panOffset.
        return target + SIMD3(x, y, z) + panOffset
    }

    /// World-space look-at point (orbit pivot shifted by panOffset).
    var lookAt: SIMD3<Float> {
        target + panOffset
    }

    var viewProjection: simd_float4x4 {
        projection * view
    }

    /// Viewprojection with an explicit aspect — use on the render thread
    /// so `aspect` is never written into the shared camera box during a draw call.
    func viewProjection(aspect: Float) -> simd_float4x4 {
        Self.perspective(fovY: fovY, aspect: aspect, near: near, far: far) * view
    }

    var view: simd_float4x4 {
        // Build the base look-at vectors.
        let eye = position
        let center = lookAt
        let f = simd_normalize(center - eye)                    // forward
        let worldUp = SIMD3<Float>(0, 1, 0)
        let s0 = simd_normalize(simd_cross(f, worldUp))         // right (pre-roll)
        let u0 = simd_cross(s0, f)                              // up (pre-roll)

        // Apply roll around the forward axis.
        let cosR = cos(roll), sinR = sin(roll)
        let s = s0 * cosR + u0 * sinR                           // right (post-roll)
        let u = u0 * cosR - s0 * sinR                           // up (post-roll)

        return simd_float4x4(
            SIMD4(s.x, u.x, -f.x, 0),
            SIMD4(s.y, u.y, -f.y, 0),
            SIMD4(s.z, u.z, -f.z, 0),
            SIMD4(-simd_dot(s, eye), -simd_dot(u, eye), simd_dot(f, eye), 1))
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
