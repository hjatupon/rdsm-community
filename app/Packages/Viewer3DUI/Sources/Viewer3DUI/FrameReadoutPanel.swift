import SwiftUI
import TFTree

/// Bottom-left overlay panel showing position/rotation readout for a selected TF frame.
struct FrameReadoutPanel: View {
    let frameName: String
    let tfTree: TFTree
    let fixedFrame: String

    @State private var edgeInfo: TFEdgeInfo?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "scope")
                    .font(.system(size: 10))
                    .foregroundStyle(.tint)
                Text(frameName)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.primary)
                Spacer()
                Button {
                    edgeInfo = nil
                    // Clear selection via notification
                    NotificationCenter.default.post(name: .frameInspectorClear, object: nil)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Clear frame selection and hide the readout panel")
                .accessibilityLabel("Clear selection")
            }

            Divider()

            if let info = edgeInfo {
                // Position
                let t = info.translation
                detailRow("pos", value: String(format: "x  %.3f  y  %.3f  z  %.3f", t.x, t.y, t.z))

                // Rotation
                let r = info.rotation
                detailRow("rot", value: String(format: "r  %.1f°  p  %.1f°  y  %.1f°", r.roll, r.pitch, r.yaw))

                if !info.isStatic {
                    // Publish rate
                    detailRow("Hz", value: String(format: "%.1f", info.hz))

                    // Staleness age
                    let age = wallClockAge(info)
                    detailRow("age", value: age)

                    // Latency
                    if info.latencyNs > 0 && info.latencyNs < 10_000_000_000 {
                        let ms = Double(info.latencyNs) / 1_000_000.0
                        let color: Color = ms < 50 ? .green : ms < 200 ? .orange : .red
                        detailRow("lat", value: String(format: "%.1f ms", ms))
                            .foregroundStyle(color)
                    }
                }

                // Source
                detailRow("src", value: info.isStatic ? "[static]" : "/tf")
            } else {
                Text("Loading…")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(minWidth: 280)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.3), radius: 8, y: 2)
        .task(id: frameName) {
            await loadEdgeInfo()
        }
    }

    private func loadEdgeInfo() async {
        let edges = await tfTree.edgesWithMetadata()
        edgeInfo = edges.first { $0.child == frameName }
    }

    private func wallClockAge(_ info: TFEdgeInfo) -> String {
        guard !info.isStatic else { return "—" }
        let nowNs = UInt64(Date().timeIntervalSince1970 * 1_000_000_000)
        guard nowNs > info.receivedAtNs else { return "0.00s" }
        let age = Double(nowNs - info.receivedAtNs) / 1_000_000_000.0
        if age < 1.0 { return String(format: "%.2fs", age) }
        if age < 60.0 { return String(format: "%.1fs", age) }
        return String(format: "%.0fs", age)
    }

    @ViewBuilder
    private func detailRow(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .trailing)
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.primary)
        }
    }
}

public extension Notification.Name {
    static let frameInspectorClear = Notification.Name("com.jatupon.ros2studio.frameInspectorClear")
    static let jumpToFrame = Notification.Name("com.jatupon.ros2studio.jumpToFrame")
    static let tfFrameBecameStale = Notification.Name("com.jatupon.ros2studio.tfFrameBecameStale")
    static let mapTooLarge = Notification.Name("com.jatupon.ros2studio.mapTooLarge")
}
