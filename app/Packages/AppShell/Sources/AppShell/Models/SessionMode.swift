import SwiftUI

public enum SessionMode: String, CaseIterable, Identifiable {
    case live = "Live Robot"
    case replay = "Rosbag Replay"

    public var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .live: "antenna.radiowaves.left.and.right"
        case .replay: "arrow.triangle.2.circlepath"
        }
    }

    var tint: Color {
        switch self {
        case .live: .green
        case .replay: .orange
        }
    }

    var description: String {
        switch self {
        case .live: "Connect to a live ROS2 robot via rosbridge to inspect topics, visualize sensor data, and debug your system in real time."
        case .replay: "Open an MCAP rosbag file for offline analysis — replay recorded sensor data, step through messages, and inspect every frame."
        }
    }

    var capabilitiesDescription: String {
        switch self {
        case .live: "Live topic browsing, 3D visualization, parameter editing, TF tree, logging, message publishing, Nav2 goal"
        case .replay: "MCAP file playback, timeline scrubber, 3D visualization, TF tree, logging, message inspection"
        }
    }
}
