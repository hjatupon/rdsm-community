/// A snapshot of joint positions, keyed by joint name. Values are radians for
/// revolute/continuous joints and metres for prismatic joints. Joints absent from the
/// dictionary are treated as being at position 0.
public struct JointState: Sendable {
    public let positions: [String: Double]

    public init(positions: [String: Double]) {
        self.positions = positions
    }

    public static let zero = JointState(positions: [:])
}
