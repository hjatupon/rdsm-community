import Logging
import simd
import Testing
@testable import RobotModelRenderer

@Suite("Model tree")
struct ModelTreeTests {
    @Test
    func `FK is cached and recomputed only when the joint state changes`() {
        let model = RobotModel(
            links: [Link(name: "base", meshKey: nil), Link(name: "a", meshKey: nil)],
            joints: [Joint(
                name: "j",
                parent: "base",
                child: "a",
                type: .revolute,
                axis: SIMD3(0, 0, 1),
                origin: .identity)],
            rootLink: "base")
        let cache = FKCache()
        let logger = Logger(subsystem: "test", category: "fk")

        _ = cache.transforms(model: model, state: JointState(positions: ["j": 0]), logger: logger)
        _ = cache.transforms(model: model, state: JointState(positions: ["j": 0]), logger: logger)
        #expect(cache.solveCount == 1) // same state → reused

        _ = cache.transforms(model: model, state: JointState(positions: ["j": 1]), logger: logger)
        #expect(cache.solveCount == 2) // changed state → recomputed
    }

    @Test
    func `A joint with an unknown child is skipped without crashing`() {
        let model = RobotModel(
            links: [Link(name: "base", meshKey: nil), Link(name: "a", meshKey: nil)],
            joints: [
                Joint(name: "ok", parent: "base", child: "a", type: .fixed, axis: SIMD3(0, 0, 1), origin: .identity),
                Joint(name: "bad", parent: "a", child: "ghost", type: .fixed, axis: SIMD3(0, 0, 1), origin: .identity),
            ],
            rootLink: "base")
        let world = ForwardKinematics.solve(model: model, state: .zero)
        #expect(world["base"] != nil)
        #expect(world["a"] != nil)
        #expect(world["ghost"] == nil)
    }

    @Test
    func `A cycle is detected and does not hang the solver`() {
        let model = RobotModel(
            links: [Link(name: "base", meshKey: nil), Link(name: "a", meshKey: nil), Link(name: "b", meshKey: nil)],
            joints: [
                Joint(name: "j1", parent: "base", child: "a", type: .fixed, axis: SIMD3(0, 0, 1), origin: .identity),
                Joint(name: "j2", parent: "a", child: "b", type: .fixed, axis: SIMD3(0, 0, 1), origin: .identity),
                Joint(name: "j3", parent: "b", child: "a", type: .fixed, axis: SIMD3(0, 0, 1), origin: .identity),
            ],
            rootLink: "base")
        #expect(ModelValidation.hasCycle(model: model))
        // Solver still terminates and returns the reachable links.
        let world = ForwardKinematics.solve(model: model, state: .zero)
        #expect(world["a"] != nil)
    }

    @Test
    func `Links whose mesh key is missing are reported as skipped`() {
        let model = RobotModel(
            links: [
                Link(name: "base", meshKey: "present"),
                Link(name: "a", meshKey: "absent"),
                Link(name: "frame", meshKey: nil),
            ],
            joints: [Joint(name: "j", parent: "base", child: "a", type: .fixed, axis: SIMD3(0, 0, 1), origin: .identity)],
            rootLink: "base")
        let skipped = ModelValidation.skippedLinks(model: model, availableMeshKeys: ["present"])
        #expect(skipped == ["a"])
    }

    @Test
    func `Unreachable links are detected`() {
        let model = RobotModel(
            links: [Link(name: "base", meshKey: nil), Link(name: "island", meshKey: nil)],
            joints: [],
            rootLink: "base")
        #expect(ModelValidation.unreachableLinks(model: model) == ["island"])
    }
}
