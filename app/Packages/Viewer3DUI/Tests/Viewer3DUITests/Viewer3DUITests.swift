import Testing
import simd
@testable import Viewer3DUI

// MARK: - CameraState tests

@Suite("CameraStateTests")
struct CameraStateTests {

    // MARK: Position

    @Test("default position is behind and above target")
    func testDefaultPosition() {
        let cam = CameraState(azimuth: 0, elevation: 0, distance: 5, target: .zero)
        let pos = cam.position
        // azimuth=0, elevation=0 → looking from +Z axis
        #expect(abs(pos.x) < 1e-5)
        #expect(abs(pos.y) < 1e-5)
        #expect(abs(pos.z - 5) < 1e-5)
    }

    @Test("position at azimuth π/2 is on +X side")
    func testAzimuthQuarterTurn() {
        let cam = CameraState(azimuth: .pi / 2, elevation: 0, distance: 5, target: .zero)
        let pos = cam.position
        #expect(abs(pos.x - 5) < 1e-5)
        #expect(abs(pos.y) < 1e-5)
        #expect(abs(pos.z) < 1e-5)
    }

    @Test("elevation raises camera above horizontal plane")
    func testElevationRaisesCamera() {
        let cam = CameraState(azimuth: 0, elevation: .pi / 4, distance: 5, target: .zero)
        #expect(cam.position.y > 0)
    }

    @Test("distance is maintained")
    func testDistance() {
        let cam = CameraState(azimuth: 0.3, elevation: 0.5, distance: 7, target: .zero)
        let dist = simd_length(cam.position - cam.target)
        #expect(abs(dist - 7) < 1e-4)
    }

    @Test("target offset shifts position")
    func testTargetOffset() {
        let t = SIMD3<Float>(1, 2, 3)
        let cam0 = CameraState(azimuth: 0, elevation: 0, distance: 5, target: .zero)
        let camT = CameraState(azimuth: 0, elevation: 0, distance: 5, target: t)
        let diff = camT.position - cam0.position
        #expect(abs(diff.x - t.x) < 1e-5)
        #expect(abs(diff.y - t.y) < 1e-5)
        #expect(abs(diff.z - t.z) < 1e-5)
    }

    @Test("distance is clamped above zero")
    func testDistanceClamped() {
        let cam = CameraState(azimuth: 0, elevation: 0, distance: -10, target: .zero)
        #expect(cam.distance > 0)
    }

    @Test("elevation is clamped near ±π/2")
    func testElevationClamped() {
        let camHigh = CameraState(azimuth: 0, elevation: .pi, target: .zero)
        let camLow  = CameraState(azimuth: 0, elevation: -.pi, target: .zero)
        #expect(camHigh.elevation < .pi / 2)
        #expect(camLow.elevation  > -.pi / 2)
    }

    // MARK: View matrix

    @Test("viewMatrix looks toward target from +Z")
    func testViewMatrixLookingDown() {
        let cam = CameraState(azimuth: 0, elevation: 0, distance: 5, target: .zero)
        let vm = cam.viewMatrix
        // Transform the target (origin) into camera space — should land near (0, 0, negative)
        let inCam = vm * SIMD4<Float>(0, 0, 0, 1)
        #expect(inCam.z < 0)           // target is in front (negative Z in camera space)
        #expect(abs(inCam.x) < 1e-4)
        #expect(abs(inCam.y) < 1e-4)
    }

    @Test("projection matrix aspect scales X column")
    func testProjectionAspect() {
        let cam = CameraState.default
        let proj1 = cam.projectionMatrix(aspect: 1)
        let proj2 = cam.projectionMatrix(aspect: 2)
        // Wider aspect → smaller X scale factor
        #expect(proj2.columns.0.x < proj1.columns.0.x)
    }

    // MARK: Interaction

    @Test("orbited shifts azimuth by delta")
    func testOrbitedAzimuth() {
        let cam = CameraState(azimuth: 0, elevation: 0, distance: 5, target: .zero)
        let cam2 = cam.orbited(deltaX: 100, deltaY: 0, sensitivity: 0.01)
        #expect(cam2.azimuth < cam.azimuth)   // negative delta: azimuth decreases
    }

    @Test("zoomed in decreases distance")
    func testZoomedIn() {
        let cam = CameraState(azimuth: 0, elevation: 0, distance: 10, target: .zero)
        let zoomed = cam.zoomed(factor: 2)
        #expect(zoomed.distance < cam.distance)
    }
}

// MARK: - SceneNode tests

@Suite("SceneNodeTests")
struct SceneNodeTests {

    @Test("leaf node has no children")
    func testLeafNode() {
        let node = SceneNode(id: "base")
        #expect(node.children.isEmpty)
    }

    @Test("identity local transform → world matches parent")
    func testIdentityLocal() {
        let node = SceneNode(id: "a", localTransform: matrix_identity_float4x4)
        let parent = translationMatrix(tx: 1, ty: 2, tz: 3)
        let world = node.worldTransform(parentWorld: parent)
        let expected = parent * matrix_identity_float4x4
        #expect(matricesApproxEqual(world, expected))
    }

    @Test("world transform composes parent × local")
    func testWorldTransformComposition() {
        let parentMat = translationMatrix(tx: 1, ty: 0, tz: 0)
        let localMat  = translationMatrix(tx: 0, ty: 2, tz: 0)
        let node = SceneNode(id: "child", localTransform: localMat)
        let world = node.worldTransform(parentWorld: parentMat)
        let point = world * SIMD4<Float>(0, 0, 0, 1)
        #expect(abs(point.x - 1) < 1e-5)
        #expect(abs(point.y - 2) < 1e-5)
        #expect(abs(point.z)     < 1e-5)
    }

    @Test("chain of three nodes accumulates translations")
    func testChainOfThree() {
        let t1 = translationMatrix(tx: 1, ty: 0, tz: 0)
        let t2 = translationMatrix(tx: 0, ty: 1, tz: 0)
        let t3 = translationMatrix(tx: 0, ty: 0, tz: 1)
        let child2 = SceneNode(id: "c2", localTransform: t3)
        let child1 = SceneNode(id: "c1", localTransform: t2, children: [child2])
        let root   = SceneNode(id: "root", localTransform: t1, children: [child1])

        let all = root.allWorldTransforms()
        let world = all["c2"]!
        let pt = world * SIMD4<Float>(0, 0, 0, 1)
        #expect(abs(pt.x - 1) < 1e-5)
        #expect(abs(pt.y - 1) < 1e-5)
        #expect(abs(pt.z - 1) < 1e-5)
    }

    @Test("allWorldTransforms includes all node ids")
    func testAllWorldTransformsKeys() {
        let child = SceneNode(id: "child")
        let root  = SceneNode(id: "root", children: [child])
        let all   = root.allWorldTransforms()
        #expect(all.keys.contains("root"))
        #expect(all.keys.contains("child"))
        #expect(all.count == 2)
    }

    @Test("allWorldTransforms with no children contains only self")
    func testSingleNodeAllTransforms() {
        let node = SceneNode(id: "solo", localTransform: translationMatrix(tx: 5, ty: 0, tz: 0))
        let all = node.allWorldTransforms()
        #expect(all.count == 1)
        let pt = all["solo"]! * SIMD4<Float>(0, 0, 0, 1)
        #expect(abs(pt.x - 5) < 1e-5)
    }
}

// MARK: - Viewer3DConfig tests

@Suite("Viewer3DConfigTests")
struct Viewer3DConfigTests {
    @Test("default fixedFrame is world")
    func testDefaultFixedFrame() {
        let cfg = Viewer3DConfig()
        #expect(cfg.fixedFrame == "world")
    }

    @Test("default topics are empty")
    func testDefaultTopics() {
        let cfg = Viewer3DConfig()
        #expect(cfg.pointCloudTopics.isEmpty)
        #expect(cfg.markerTopics.isEmpty)
    }

    @Test("custom init sets fields correctly")
    func testCustomInit() {
        let cfg = Viewer3DConfig(
            pointCloudTopics: ["/scan"],
            markerTopics: ["/markers"],
            fixedFrame: "map")
        #expect(cfg.pointCloudTopics == ["/scan"])
        #expect(cfg.markerTopics == ["/markers"])
        #expect(cfg.fixedFrame == "map")
    }

    @Test("equality holds for same values")
    func testEquality() {
        let a = Viewer3DConfig(pointCloudTopics: ["/t"], fixedFrame: "odom")
        let b = Viewer3DConfig(pointCloudTopics: ["/t"], fixedFrame: "odom")
        #expect(a == b)
    }
}

// MARK: - Helpers

private func translationMatrix(tx: Float, ty: Float, tz: Float) -> simd_float4x4 {
    var m = matrix_identity_float4x4
    m.columns.3 = SIMD4(tx, ty, tz, 1)
    return m
}

private func matricesApproxEqual(_ a: simd_float4x4, _ b: simd_float4x4, eps: Float = 1e-5) -> Bool {
    let pairs: [(SIMD4<Float>, SIMD4<Float>)] = [
        (a.columns.0, b.columns.0),
        (a.columns.1, b.columns.1),
        (a.columns.2, b.columns.2),
        (a.columns.3, b.columns.3),
    ]
    for (ac, bc) in pairs {
        let diff = abs(ac - bc)
        if diff.x > eps || diff.y > eps || diff.z > eps || diff.w > eps { return false }
    }
    return true
}
