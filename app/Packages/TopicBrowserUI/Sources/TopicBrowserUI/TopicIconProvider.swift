import Foundation

/// Maps ROS2 schema families to SF Symbols.
///
/// The mapping covers the most common message families in robotics; unknown
/// schemas fall back to `"dot.radiowaves.left.and.right"`.
public struct TopicIconProvider: Sendable {

    public static func icon(for schemaName: String) -> String {
        let lower = schemaName.lowercased()

        if lower.contains("image") || lower.contains("compressed") {
            return "camera.fill"
        }
        if lower.contains("pointcloud") || lower.contains("point_cloud") {
            return "cube.fill"
        }
        if lower.contains("laserscan") || lower.contains("laser_scan") || lower.contains("range") {
            return "sensor.tag.radiowaves.forward.fill"
        }
        if lower.contains("imu") || lower.contains("magneticfield") {
            return "gyroscope"
        }
        if lower.contains("pose") || lower.contains("transform") || lower.contains("odometry") {
            return "arrow.up.forward.circle.fill"
        }
        if lower.contains("twist") || lower.contains("accel") || lower.contains("wrench") {
            return "arrow.up.and.down.and.arrow.left.and.right"
        }
        if lower.contains("path") || lower.contains("polygon") || lower.contains("polyline") {
            return "point.topleft.down.to.point.bottomright.curvepath.fill"
        }
        if lower.contains("marker") || lower.contains("markerarray") {
            return "mappin.circle.fill"
        }
        if lower.contains("jointstate") || lower.contains("joint_state") {
            return "figure.arms.open"
        }
        if lower.contains("log") || lower.contains("string") || lower.contains("header") {
            return "text.alignleft"
        }
        if lower.contains("bool") || lower.contains("int") || lower.contains("float") || lower.contains("uint") {
            return "number.circle.fill"
        }
        if lower.contains("battery") || lower.contains("power") {
            return "battery.100.bolt"
        }
        if lower.contains("gps") || lower.contains("navsatfix") || lower.contains("navsat") {
            return "location.fill"
        }
        if lower.contains("clock") || lower.contains("time") || lower.contains("duration") {
            return "clock.fill"
        }
        if lower.contains("joy") || lower.contains("gamepad") {
            return "gamecontroller.fill"
        }
        return "dot.radiowaves.left.and.right"
    }

    /// A short human-readable family label derived from the schema package prefix.
    public static func familyLabel(for schemaName: String) -> String {
        let parts = schemaName.split(separator: "/")
        return parts.first.map(String.init) ?? schemaName
    }
}
