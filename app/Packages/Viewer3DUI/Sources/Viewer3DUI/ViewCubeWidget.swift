import SwiftUI
import PointCloudRenderer

/// A SolidWorks-style 2D orientation cube widget rendered as a SwiftUI overlay.
///
/// Shows the current camera orientation with labelled face buttons.
/// Clicking a face snaps the camera to that standard view.
/// Clicking an edge snaps to a 45-degree diagonal view.
/// Clicking a corner snaps to isometric (45° azimuth, 35.26° elevation).
///
/// Designed to sit in the bottom-left corner of the 3D viewport.
struct ViewCubeWidget: View {
    /// Current camera azimuth in radians (from PointCloudRenderer).
    let azimuth: Float
    /// Current camera elevation in radians.
    let elevation: Float

    /// Called when user clicks a snap view. The caller applies it to the renderer.
    let onSnap: (SnapView) -> Void

    // MARK: - Snap views

    enum SnapView {
        case front, back, left, right, top, bottom
        case frontRight, frontLeft, backRight, backLeft  // edges
        case topFrontRight, topFrontLeft, topBackRight, topBackLeft  // corners (isometric)

        var azimuth: Float {
            switch self {
            case .front:          return 0
            case .back:           return .pi
            case .right:          return .pi / 2
            case .left:           return -.pi / 2
            case .top:            return 0
            case .bottom:         return 0
            case .frontRight:     return .pi / 4
            case .frontLeft:      return -.pi / 4
            case .backRight:      return 3 * .pi / 4
            case .backLeft:       return -3 * .pi / 4
            case .topFrontRight:  return .pi / 4
            case .topFrontLeft:   return -.pi / 4
            case .topBackRight:   return 3 * .pi / 4
            case .topBackLeft:    return -3 * .pi / 4
            }
        }

        var elevation: Float {
            switch self {
            case .front, .back, .left, .right:
                return 0
            case .top:
                return .pi / 2 - 0.01
            case .bottom:
                return -(.pi / 2 - 0.01)
            case .frontRight, .frontLeft, .backRight, .backLeft:
                return 0
            case .topFrontRight, .topFrontLeft, .topBackRight, .topBackLeft:
                // True isometric: arctan(1/√2) ≈ 35.26°
                return atan(1.0 / sqrt(2.0))
            }
        }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            // Background capsule
            RoundedRectangle(cornerRadius: 10)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.secondary.opacity(0.25), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.3), radius: 4, y: 2)

            VStack(spacing: 3) {
                // Label
                Text("VIEW")
                    .font(.system(size: 7, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)

                // Cube face grid (3×3: corners + edges + faces)
                cubeGrid
            }
            .padding(8)
        }
        .frame(width: 82, height: 86)
    }

    // MARK: - Cube Grid

    private var cubeGrid: some View {
        // 3×3 grid representing the cube in a fixed world orientation.
        // Labels are static world-face labels (SolidWorks convention):
        // clicking "Front" always snaps to the front view, regardless of
        // current camera azimuth. The compass-arrow indicator conveys orientation.
        VStack(spacing: 2) {
            HStack(spacing: 2) {
                cubeButton(label: nil, systemImage: "arrow.up.left", snap: .topFrontLeft, size: 16)
                cubeButton(label: "T", systemImage: nil, snap: .top, size: 22)
                cubeButton(label: nil, systemImage: "arrow.up.right", snap: .topFrontRight, size: 16)
            }
            HStack(spacing: 2) {
                cubeButton(label: "L", systemImage: nil, snap: .left, size: 22)
                orientationIndicator
                    .frame(width: 24, height: 22)
                cubeButton(label: "R", systemImage: nil, snap: .right, size: 22)
            }
            HStack(spacing: 2) {
                cubeButton(label: nil, systemImage: "arrow.down.left", snap: .frontLeft, size: 16)
                cubeButton(label: "F", systemImage: nil, snap: .front, size: 22)
                cubeButton(label: nil, systemImage: "arrow.down.right", snap: .frontRight, size: 16)
            }
        }
    }

    // MARK: - Orientation indicator (mini compass-style)

    /// Small 2D compass rose showing current camera direction.
    private var orientationIndicator: some View {
        ZStack {
            // Background circle
            Circle()
                .fill(Color.accentColor.opacity(0.08))
                .overlay(Circle().stroke(Color.accentColor.opacity(0.3), lineWidth: 0.5))

            // North arrow (current camera facing direction)
            let angle = Double(azimuth)
            let arrowLength: CGFloat = 8
            let dx = arrowLength * sin(angle)
            let dy = -arrowLength * cos(angle)

            // Forward direction arrow
            Path { p in
                p.move(to: CGPoint(x: 12, y: 11))
                p.addLine(to: CGPoint(x: 12 + dx, y: 11 + dy))
            }
            .stroke(Color.accentColor, lineWidth: 1.5)
            .frame(width: 24, height: 22)

            // Center dot
            Circle()
                .fill(Color.accentColor)
                .frame(width: 3, height: 3)
        }
    }

    // MARK: - Button builder

    @ViewBuilder
    private func cubeButton(label: String?, systemImage: String?, snap: SnapView, size: CGFloat) -> some View {
        Button {
            onSnap(snap)
        } label: {
            Group {
                if let label {
                    Text(label)
                        .font(.system(size: size == 22 ? 9 : 7, weight: .semibold, design: .monospaced))
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 6))
                }
            }
            .frame(width: size, height: size == 22 ? 16 : 14)
            .background(faceBgColor(for: snap), in: RoundedRectangle(cornerRadius: 3))
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .foregroundStyle(faceFgColor(for: snap))
        .help(snapLabel(for: snap))
    }

    private func faceBgColor(for snap: SnapView) -> Color {
        switch snap {
        case .top:    return Color(.sRGB, red: 0.9, green: 0.5, blue: 0.3, opacity: 0.85)
        case .front:  return Color(.sRGB, red: 0.3, green: 0.65, blue: 0.9, opacity: 0.85)
        case .right:  return Color(.sRGB, red: 0.3, green: 0.8, blue: 0.4, opacity: 0.85)
        case .back:   return Color(.sRGB, red: 0.3, green: 0.65, blue: 0.9, opacity: 0.5)
        case .left:   return Color(.sRGB, red: 0.3, green: 0.8, blue: 0.4, opacity: 0.5)
        case .bottom: return Color(.sRGB, red: 0.9, green: 0.5, blue: 0.3, opacity: 0.5)
        default:      return Color.secondary.opacity(0.12)
        }
    }

    private func faceFgColor(for snap: SnapView) -> Color {
        switch snap {
        case .top, .front, .right: return .white
        default:                    return Color.secondary
        }
    }

    private func snapLabel(for snap: SnapView) -> String {
        switch snap {
        case .front:         return "Front view"
        case .back:          return "Back view"
        case .left:          return "Left view"
        case .right:         return "Right view"
        case .top:           return "Top view"
        case .bottom:        return "Bottom view"
        case .frontRight:    return "Front-Right diagonal"
        case .frontLeft:     return "Front-Left diagonal"
        case .backRight:     return "Back-Right diagonal"
        case .backLeft:      return "Back-Left diagonal"
        case .topFrontRight: return "Isometric: Top-Front-Right"
        case .topFrontLeft:  return "Isometric: Top-Front-Left"
        case .topBackRight:  return "Isometric: Top-Back-Right"
        case .topBackLeft:   return "Isometric: Top-Back-Left"
        }
    }
}
