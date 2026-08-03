import SwiftUI

/// Persistent clickable status bar at the bottom of MainWindow.
/// Tapping anywhere opens/closes the PerformancePanelView slide-up overlay.
struct PerformanceFooterBar: View {
    @Binding var showPanel: Bool
    @Environment(PerformanceDashboard.self) private var dashboard
    @Environment(PerformanceStore.self) private var store

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    showPanel.toggle()
                }
            } label: {
                HStack(spacing: 0) {
                    presetBadge
                    separator
                    metricChip(icon: "display", value: fpsLabel)
                    separator
                    cpuChip
                    separator
                    metricChip(icon: "memorychip", value: memLabel)
                    separator
                    topicChip
                    Spacer(minLength: 8)
                    expandChevron
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(showPanel ? Color.ros2Accent.opacity(0.06) : Color.clear)
        }
        .background(.ultraThinMaterial)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Subviews

    private var presetBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: store.preset.icon)
                .font(.caption2)
            Text(store.preset.label)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(presetColor)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(presetColor.opacity(0.12), in: Capsule())
    }

    private var cpuChip: some View {
        HStack(spacing: 5) {
            Image(systemName: "cpu")
                .font(.caption2)
            Text(String(format: "%.0f%%", dashboard.cpuPercent))
                .font(.caption.monospacedDigit())
            Capsule()
                .fill(Color.ros2Accent.opacity(0.25))
                .frame(width: 40, height: 4)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(cpuBarColor)
                        .frame(width: 40 * min(1, dashboard.cpuPercent / 100), height: 4)
                }
        }
        .foregroundStyle(Color.secondary)
    }

    private var topicChip: some View {
        HStack(spacing: 3) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.caption2)
            if dashboard.topicCount > 0 {
                Text("\(dashboard.topicCount) topics · \(msgRateLabel)")
                    .font(.caption.monospacedDigit())
            } else {
                Text("—")
                    .font(.caption)
            }
        }
        .foregroundStyle(Color.secondary)
    }

    private var expandChevron: some View {
        Image(systemName: showPanel ? "chevron.down" : "chevron.up")
            .font(.caption2.weight(.medium))
            .foregroundStyle(Color.ros2Accent.opacity(0.8))
            .padding(.leading, 8)
            .animation(.easeInOut(duration: 0.15), value: showPanel)
    }

    private var separator: some View {
        Color.secondary.opacity(0.2)
            .frame(width: 1, height: 14)
            .padding(.horizontal, 8)
    }

    private func metricChip(icon: String, value: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.caption2)
            Text(value).font(.caption.monospacedDigit())
        }
        .foregroundStyle(Color.secondary)
    }

    // MARK: - Computed labels

    private var fpsLabel: String {
        let target = store.renderFPS
        let actual = dashboard.actualFPS
        guard actual >= 1 else { return "\(target) fps" }
        return String(format: "%.0f/\(target) fps", actual)
    }

    private var memLabel: String {
        let mb = dashboard.memoryMB
        return mb < 1024
            ? String(format: "%.0f MB", mb)
            : String(format: "%.1f GB", mb / 1024)
    }

    private var msgRateLabel: String {
        let r = dashboard.messageRate
        guard r >= 1 else { return "< 1 msg/s" }
        return String(format: "%.0f msg/s", r)
    }

    private var presetColor: Color {
        switch store.preset {
        case .eco:         return .ros2Accent
        case .balanced:    return .secondary
        case .performance: return .yellow
        case .custom:      return .orange
        }
    }

    private var cpuBarColor: Color {
        switch dashboard.cpuPercent {
        case ..<50: return .ros2Accent
        case ..<80: return .orange
        default:    return .red
        }
    }
}
