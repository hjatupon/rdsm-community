import SwiftUI

/// Active drag mode for the 3D viewer.
public enum CameraTool: Sendable, Equatable {
    /// Yaw — rotate around the world vertical axis (left/right drag).
    case yaw
    /// Pitch — tilt the camera up/down (up/down drag).
    case pitch
    /// Roll — bank the camera around the view-forward axis (left/right drag).
    case roll
    /// Pan — translate target on world X/Y axes (pure translation, no rotation).
    case pan
    /// SolidWorks-style orbit — combined rotate+pan in one tool.
    /// Left drag: yaw+pitch orbit. Shift+drag: pan. Option/Right-drag: roll.
    case orbit
    /// Nav Goal — click+drag to place a 2D navigation goal pose on the floor plane.
    /// Click sets XY position; drag direction sets heading (yaw). On release, publishes
    /// geometry_msgs/msg/PoseStamped to /goal_pose.
    case navGoal
    /// Pose Estimate — click+drag to set robot initial pose for AMCL re-initialization.
    /// Click sets XY position; drag direction sets heading (yaw). On release, publishes
    /// geometry_msgs/msg/PoseWithCovarianceStamped to /initialpose.
    case poseEstimate
}

/// Floating bottom-center toolbar overlay for 3D viewer camera control.
/// Includes the fixed-frame picker on the left side when a connection is active.
struct CameraToolbar: View {
    @Binding var activeTool: CameraTool
    let onZoomIn:  () -> Void
    let onZoomOut: () -> Void
    let onFit:     () -> Void
    let onTopView: () -> Void
    let fixedFrameBinding: Binding<String>?
    let availableFrames: [String]
    let onFixedFrameChange: ((String) -> Void)?

    var body: some View {
        HStack(spacing: 2) {
            if let binding = fixedFrameBinding, !availableFrames.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "globe")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("Fixed Frame", selection: Binding(
                        get: { binding.wrappedValue },
                        set: { newValue in
                            binding.wrappedValue = newValue
                            onFixedFrameChange?(newValue)
                        }
                    )) {
                        ForEach(availableFrames, id: \.self) { frame in
                            Text(frame).tag(frame)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }
                .padding(.leading, 4)
                .padding(.trailing, 2)

                divider
            }

            // SolidWorks-style multi-action orbit button — first/prominent
            modeButton("rotate.3d",
                       tool: .orbit, label: "Orbit (SolidWorks style: drag=yaw+pitch, Shift=pan, Option=roll)")

            divider

            modeButton("arrow.left.and.right",
                       tool: .roll,  label: "Roll (drag left/right to bank around the forward axis)")
            modeButton("arrow.up.and.down",
                       tool: .pitch, label: "Pitch (drag up/down to tilt the camera)")
            modeButton("arrow.clockwise",
                       tool: .yaw,   label: "Yaw (drag left/right to rotate around the world vertical axis)")
            modeButton("arrow.up.and.down.and.arrow.left.and.right",
                       tool: .pan,   label: "Pan (drag to translate — no rotation)")

            divider

            actionButton("plus.magnifyingglass",
                         label: "Zoom In",   action: onZoomIn)
            actionButton("minus.magnifyingglass",
                         label: "Zoom Out",  action: onZoomOut)
            actionButton("arrow.up.left.and.down.right.magnifyingglass",
                         label: "Fit / Reset view", action: onFit)
            actionButton("square.3.layers.3d.top.filled",
                         label: "Top view",  action: onTopView)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
    }

    // MARK: - Private

    @ViewBuilder
    private func modeButton(_ icon: String, tool: CameraTool, label: String) -> some View {
        let isActive = activeTool == tool
        Button { activeTool = tool } label: {
            Image(systemName: icon)
                .frame(width: 24, height: 24)
                .background(
                    isActive ? Color.accentColor.opacity(0.18) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .foregroundStyle(isActive ? Color.accentColor : Color.primary)
        .help(label)
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private func actionButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .help(label)
        .accessibilityLabel(label)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.35))
            .frame(width: 1, height: 16)
            .padding(.horizontal, 3)
    }
}
