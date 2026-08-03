import simd
import Testing
@testable import RobotModelRenderer

@Suite("ForwardKinematics")
struct ForwardKinematicsTests {
    /// A 3-link chain: base —(revolute z)→ a —(prismatic x)→ b, with fixed origins.
    private func chain() -> RobotModel {
        let links = [Link(name: "base", meshKey: nil), Link(name: "a", meshKey: nil), Link(name: "b", meshKey: nil)]
        let joints = [
            Joint(
                name: "j1",
                parent: "base",
                child: "a",
                type: .revolute,
                axis: SIMD3(0, 0, 1),
                origin: Transform(translation: SIMD3(1, 0, 0))),
            Joint(
                name: "j2",
                parent: "a",
                child: "b",
                type: .prismatic,
                axis: SIMD3(1, 0, 0),
                origin: Transform(translation: SIMD3(0, 1, 0))),
        ]
        return RobotModel(links: links, joints: joints, rootLink: "base")
    }

    private func translation(_ m: simd_float4x4) -> SIMD3<Float> {
        SIMD3(m.columns.3.x, m.columns.3.y, m.columns.3.z)
    }

    @Test
    func `World transforms match an independent hand computation within 1e-4`() throws {
        let model = chain()
        let state = JointState(positions: ["j1": .pi / 2, "j2": 0.5])
        let world = ForwardKinematics.solve(model: model, state: state)

        // Independent path: build the chain explicitly with simd primitives.
        let rz = simd_float4x4(simd_quatf(angle: .pi / 2, axis: SIMD3(0, 0, 1)))
        var t1 = matrix_identity_float4x4
        t1.columns.3 = SIMD4(1, 0, 0, 1)
        let aWorld = t1 * rz
        var t2 = matrix_identity_float4x4
        t2.columns.3 = SIMD4(0, 1, 0, 1)
        var prism = matrix_identity_float4x4
        prism.columns.3 = SIMD4(0.5, 0, 0, 1)
        let bWorld = aWorld * t2 * prism

        let solvedB = try #require(world["b"])
        #expect(simd_distance(translation(solvedB), translation(bWorld)) < 1e-4)
        // Hand-verified: j1 rotates 90° around z so a's x-axis → world y.
        // b's origin (0,1,0) in a's frame maps to world (0,0,0); prismatic 0.5
        // along a's local x (world y) yields final world position (0, 0.5, 0).
        #expect(simd_distance(translation(solvedB), SIMD3(0, 0.5, 0)) < 1e-4)
    }

    @Test
    func `The root link is at the identity transform`() throws {
        let world = ForwardKinematics.solve(model: chain(), state: .zero)
        let root = try #require(world["base"])
        #expect(simd_distance(translation(root), SIMD3(0, 0, 0)) < 1e-6)
    }

    @Test
    func `A revolute joint at zero leaves the child at its fixed origin`() throws {
        let world = ForwardKinematics.solve(model: chain(), state: .zero)
        let a = try #require(world["a"])
        #expect(simd_distance(translation(a), SIMD3(1, 0, 0)) < 1e-4)
    }
}
