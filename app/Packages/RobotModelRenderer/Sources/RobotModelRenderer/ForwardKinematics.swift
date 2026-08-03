import Logging
import simd

/// Computes per-link world transforms by walking the kinematic tree from the root,
/// composing each joint's fixed origin with its state-driven motion. Pure and
/// GPU-free, so the contract accuracy gate (≤ 1e-4 vs tf2) is unit-testable on the CPU.
enum ForwardKinematics {
    /// World transform of every link reachable from `model.rootLink`. Unreachable links
    /// (dangling parent) and cycles are skipped with a logged error rather than crashing.
    static func solve(
        model: RobotModel,
        state: JointState,
        logger: (any LoggerProtocol)? = nil) -> [String: simd_float4x4]
    {
        let linkNames = Set(model.links.map(\.name))
        // parent link → outgoing joints.
        var children: [String: [Joint]] = [:]
        for joint in model.joints {
            children[joint.parent, default: []].append(joint)
        }

        var world: [String: simd_float4x4] = [model.rootLink: matrix_identity_float4x4]
        var visited: Set<String> = [model.rootLink]
        var queue: [String] = [model.rootLink]

        while let parent = queue.popLast() {
            guard let parentWorld = world[parent] else { continue }
            for joint in children[parent] ?? [] {
                guard linkNames.contains(joint.child) else {
                    logger?.error("joint references unknown child", fields: [LogField(key: "joint", value: joint.name)])
                    continue
                }
                if visited.contains(joint.child) {
                    logger?.error("cycle detected in kinematic tree", fields: [LogField(key: "link", value: joint.child)])
                    continue
                }
                let q = state.positions[joint.name] ?? 0
                world[joint.child] = parentWorld * joint.origin.matrix * motion(of: joint, position: Float(q))
                visited.insert(joint.child)
                queue.append(joint.child)
            }
        }
        return world
    }

    /// The state-driven local motion of a joint about/along its axis.
    private static func motion(of joint: Joint, position: Float) -> simd_float4x4 {
        switch joint.type {
        case .fixed, .floating, .planar:
            // floating/planar are multi-DOF; v0.1 renders them at their origin (PENDING).
            return matrix_identity_float4x4
        case .revolute, .continuous:
            let axis = normalizedAxis(joint.axis)
            return simd_float4x4(simd_quatf(angle: position, axis: axis))
        case .prismatic:
            var m = matrix_identity_float4x4
            m.columns.3 = SIMD4<Float>(normalizedAxis(joint.axis) * position, 1)
            return m
        }
    }

    private static func normalizedAxis(_ axis: SIMD3<Float>) -> SIMD3<Float> {
        let length = simd_length(axis)
        return length > 0 ? axis / length : SIMD3<Float>(0, 0, 1)
    }
}

/// GPU-free model checks used by both ``ForwardKinematics`` and the renderer.
enum ModelValidation {
    /// Links that are not reachable from the root (dangling/disconnected subtrees).
    static func unreachableLinks(model: RobotModel) -> [String] {
        let reachable = Set(ForwardKinematics.solve(model: model, state: .zero).keys)
        return model.links.map(\.name).filter { !reachable.contains($0) }
    }

    /// `true` if the joint graph contains a cycle (would otherwise revisit a link).
    static func hasCycle(model: RobotModel) -> Bool {
        var children: [String: [String]] = [:]
        for joint in model.joints {
            children[joint.parent, default: []].append(joint.child)
        }
        var visited: Set<String> = []
        var stack = [model.rootLink]
        visited.insert(model.rootLink)
        while let node = stack.popLast() {
            for child in children[node] ?? [] {
                if visited.contains(child) { return true }
                visited.insert(child)
                stack.append(child)
            }
        }
        return false
    }

    /// Link names that declare a `meshKey` which is missing from `availableMeshKeys`;
    /// the renderer skips these (with a warning) and renders the rest.
    static func skippedLinks(model: RobotModel, availableMeshKeys: Set<String>) -> [String] {
        model.links.compactMap { link in
            guard let key = link.meshKey else { return nil }
            return availableMeshKeys.contains(key) ? nil : link.name
        }
    }
}
