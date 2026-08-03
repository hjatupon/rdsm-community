import Foundation

/// How the inspector renders a given message schema.
///
/// The schema-to-kind mapping is pure logic with no SwiftUI dependency —
/// it is the core testable unit of InspectorUI.
public enum RenderKind: Sendable, Equatable {
    /// `sensor_msgs/msg/Image` or `sensor_msgs/msg/CompressedImage` → image viewer.
    case image
    /// Single numeric scalar (int*, float*, uint*) → inline time-series chart.
    case numericScalar
    /// `std_msgs/msg/Bool` → large true/false badge.
    case boolean
    /// `std_msgs/msg/String` → large text display.
    case stringValue
    /// `rcl_interfaces/msg/Log` → scrolling log list.
    case logMessage
    /// `sensor_msgs/msg/Range` → horizontal range gauge.
    case rangeGauge
    /// `sensor_msgs/msg/BatteryState` → battery level + stats.
    case batteryState
    /// `sensor_msgs/msg/LaserScan` → polar ring chart.
    case laserScan
    /// `nav_msgs/msg/Odometry` → position / orientation / velocity dashboard.
    case odometry
    /// `sensor_msgs/msg/Imu` → roll/pitch/yaw gauges + accel/gyro values.
    case imu
    /// `geometry_msgs/msg/Twist` or `TwistStamped` → velocity gauges.
    case twist
    /// `nav_msgs/msg/OccupancyGrid` → grayscale minimap thumbnail.
    case occupancyGrid
    /// `sensor_msgs/msg/JointState` → per-joint bars (position/velocity/effort).
    case jointState
    /// `diagnostic_msgs/msg/DiagnosticArray` → status list with colored dots.
    case diagnosticArray
    /// `tf2_msgs/msg/TFMessage` → TF tree visualization (injected from host app).
    case tfTree
    /// Any struct/array/nested message → always-expanded JSON tree.
    case jsonTree
}

public struct RenderKindResolver: Sendable {

    public init() {}

    /// Resolves the render kind from a schema name.
    public func resolve(schemaName: String) -> RenderKind {
        let lower = schemaName.lowercased()

        if lower.contains("image") { return .image }
        if lower == "rcl_interfaces/msg/log" { return .logMessage }
        if lower == "sensor_msgs/msg/range" { return .rangeGauge }
        if lower == "sensor_msgs/msg/batterystate" { return .batteryState }
        if lower == "sensor_msgs/msg/laserscan" { return .laserScan }
        if lower == "nav_msgs/msg/odometry" { return .odometry }
        if lower == "sensor_msgs/msg/imu" { return .imu }
        if lower == "geometry_msgs/msg/twist" || lower == "geometry_msgs/msg/twiststamped" { return .twist }
        if lower == "nav_msgs/msg/occupancygrid" { return .occupancyGrid }
        if lower == "sensor_msgs/msg/jointstate" { return .jointState }
        if lower == "diagnostic_msgs/msg/diagnosticarray" { return .diagnosticArray }
        if lower.contains("tf2_msgs") && lower.contains("tfmessage") { return .tfTree }
        if lower.hasSuffix("/msg/bool") || lower.hasSuffix("/bool") { return .boolean }
        if lower.hasSuffix("/msg/string") || lower.hasSuffix("/string") { return .stringValue }
        if isNumericScalar(lower) { return .numericScalar }
        return .jsonTree
    }

    // MARK: - Private

    private func isNumericScalar(_ lower: String) -> Bool {
        let numericSuffixes = [
            "float32", "float64",
            "int8", "int16", "int32", "int64",
            "uint8", "uint16", "uint32", "uint64",
        ]
        for suffix in numericSuffixes {
            if lower.hasSuffix("/\(suffix)") || lower.hasSuffix("/msg/\(suffix)") {
                return true
            }
        }
        return false
    }
}
