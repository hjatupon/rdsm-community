import Testing
import RobotModelCore
import simd

@Suite("RobotModel value types")
struct RobotModelCoreTests {
    @Test func linkEquality() {
        let a = Link(name: "base", meshKey: "m")
        let b = Link(name: "base", meshKey: "m")
        #expect(a == b)
    }

    @Test func jointType_allCases() {
        let types: [JointType] = [.fixed, .revolute, .prismatic, .continuous, .floating, .planar]
        #expect(types.count == 6)
    }

    @Test func transform_identity_matrix() {
        let t = Transform.identity
        let m = t.matrix
        #expect(m == matrix_identity_float4x4)
    }

    @Test func transform_translation_roundtrip() {
        let v = SIMD3<Float>(1, 2, 3)
        let t = Transform(translation: v)
        #expect(t.matrix.columns.3.x == 1)
        #expect(t.matrix.columns.3.y == 2)
        #expect(t.matrix.columns.3.z == 3)
    }

    @Test func robotModel_init() {
        let links = [Link(name: "root", meshKey: nil)]
        let model = RobotModel(links: links, joints: [], rootLink: "root")
        #expect(model.links.count == 1)
        #expect(model.joints.isEmpty)
        #expect(model.rootLink == "root")
    }
}
