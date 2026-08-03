import Foundation
import simd
import ChartingCore
import LogStore

/// Frozen copy of InspectorViewModel's typed state.
///
/// Created once when the picker modal opens (for preview thumbnails) and
/// on every message update when an override is active (for live rendering).
/// All fields are value types or Sendable references — safe to pass across concurrency domains.
public struct VisualizationSnapshot: Sendable {

    // MARK: - Meta

    public let schemaName: String
    public let autoRenderKind: RenderKind
    public let latestPayload: Data?
    public let jsonRoots: [FieldNode]
    public let messageCount: UInt64
    public let hz: Double

    // MARK: - Numeric chart

    public let latestScalar: Double?
    public let chartSeries: ChartSeries

    // MARK: - Bool / String

    public let latestBool: Bool?
    public let latestString: String?

    // MARK: - Log

    public let logEntries: [LogEntry]

    // MARK: - Range sensor

    public let rangeValue: Double?
    public let rangeMin: Double?
    public let rangeMax: Double?

    // MARK: - Battery

    public let batteryPercentage: Double?
    public let batteryVoltage: Double?
    public let batteryCurrent: Double?

    // MARK: - LaserScan

    public let scanRanges: [Float]
    public let scanAngleMin: Double
    public let scanAngleMax: Double
    public let scanRangeMin: Double
    public let scanRangeMax: Double

    // MARK: - Odometry

    public let odomPosition: SIMD3<Double>
    public let odomRPY: SIMD3<Double>          // radians
    public let odomLinearVel: SIMD3<Double>
    public let odomAngularVel: SIMD3<Double>
    public let odomPositionTrail: [SIMD2<Double>]
    public let odomVelSeries: ChartSeries

    // MARK: - IMU

    public let imuRPY: SIMD3<Double>           // radians
    public let imuAngularVel: SIMD3<Double>
    public let imuLinearAccel: SIMD3<Double>

    // MARK: - Twist

    public let twistLinear: SIMD3<Double>
    public let twistAngular: SIMD3<Double>

    // MARK: - OccupancyGrid

    public let gridWidth: Int
    public let gridHeight: Int
    public let gridResolution: Double
    public let gridData: [Int8]

    // MARK: - JointState

    public let jointNames: [String]
    public let jointPositions: [Double]
    public let jointVelocities: [Double]
    public let jointEfforts: [Double]

    // MARK: - DiagnosticArray

    public let diagnosticItems: [DiagnosticItem]

    // MARK: - Convenience

    /// Returns the first numeric value available: scalar → range → battery → odom linear.x.
    public var firstNumericValue: Double? {
        latestScalar
            ?? rangeValue
            ?? batteryPercentage
            ?? (odomLinearVel.x != 0 ? odomLinearVel.x : nil)
    }

    /// A flat array of numeric values suitable for histograms / stats.
    /// Priority: scan ranges, joint positions, scalar series.
    public var numericArray: [Double] {
        if !scanRanges.isEmpty { return scanRanges.map(Double.init) }
        if !jointPositions.isEmpty { return jointPositions }
        return []
    }

    // MARK: - Empty placeholder

    public static let empty = VisualizationSnapshot(
        schemaName: "", autoRenderKind: .jsonTree,
        latestPayload: nil, jsonRoots: [], messageCount: 0, hz: 0,
        latestScalar: nil,
        chartSeries: ChartSeries(id: "empty", color: .zero, capacity: 64),
        latestBool: nil, latestString: nil, logEntries: [],
        rangeValue: nil, rangeMin: nil, rangeMax: nil,
        batteryPercentage: nil, batteryVoltage: nil, batteryCurrent: nil,
        scanRanges: [], scanAngleMin: 0, scanAngleMax: 0, scanRangeMin: 0, scanRangeMax: 0,
        odomPosition: .zero, odomRPY: .zero, odomLinearVel: .zero, odomAngularVel: .zero,
        odomPositionTrail: [],
        odomVelSeries: ChartSeries(id: "empty.vel", color: .zero, capacity: 64),
        imuRPY: .zero, imuAngularVel: .zero, imuLinearAccel: .zero,
        twistLinear: .zero, twistAngular: .zero,
        gridWidth: 0, gridHeight: 0, gridResolution: 0.05, gridData: [],
        jointNames: [], jointPositions: [], jointVelocities: [], jointEfforts: [],
        diagnosticItems: [])
}
