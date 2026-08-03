import SwiftUI
import Charts

/// Slide-up floating panel showing live metric charts and quick throttle controls.
/// Triggered by clicking the PerformanceFooterBar.
struct PerformancePanelView: View {
    @Binding var isPresented: Bool
    @Environment(PerformanceDashboard.self) private var dashboard
    @Environment(PerformanceStore.self) private var store
    @EnvironmentObject private var services: AppServices

    @State private var draft = PerformanceStore.DraftValues(
        lodThreshold: 500_000, renderFPS: 60, renderResolution: 0.75,
        inspectorThrottleSeconds: 0.0, topicBufferSize: 256,
        topicCacheCapacity: 1024, logCapacity: 5_000, tfHistoryDurationSec: 10.0,
        maxReconnectAttempts: 10, subscribeThrottleMs: 100, chartHistoryPoints: 2000
    )

    private var isDirty: Bool { draft != store.snapshot() }
    private var isConnected: Bool { !services.activeConnectionHandles.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            panelHandle
            header
            Divider()
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    chartsGrid
                    Divider().padding(.horizontal, 16)
                    quickControls
                }
            }
            .frame(maxHeight: 380)
        }
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 14, bottomLeadingRadius: 0,
                                          bottomTrailingRadius: 0, topTrailingRadius: 14))
        .shadow(color: .black.opacity(0.25), radius: 24, y: -4)
        .onAppear { draft = store.snapshot() }
        .onChange(of: store.preset) { _, _ in draft = store.snapshot() }
    }

    // MARK: - Handle + Header

    private var panelHandle: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Color.secondary.opacity(0.4))
            .frame(width: 36, height: 4)
            .padding(.top, 8)
            .padding(.bottom, 4)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "gauge.with.needle")
                .font(.callout)
                .foregroundStyle(Color.ros2Accent)
            Text("Performance Monitor")
                .font(.callout.weight(.semibold))

            Spacer()

            // Live status chips
            statusChip(value: String(format: "%.0f%%", dashboard.cpuPercent),
                       icon: "cpu", color: cpuColor)
            statusChip(value: memShort, icon: "memorychip", color: .secondary)
            statusChip(value: fpsShort, icon: "display", color: fpsColor)

            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    isPresented = false
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Color.secondary.opacity(0.7))
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Charts (2×2 grid)

    private var chartsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            miniChart(title: "App CPU", unit: "%",
                      current: dashboard.cpuPercent,
                      history: dashboard.cpuHistory,
                      color: cpuColor, maxY: 100)

            miniChart(title: "App Memory", unit: "MB",
                      current: dashboard.memoryMB,
                      history: dashboard.memHistory,
                      color: .blue, maxY: nil)

            miniChart(title: "Render FPS", unit: "fps",
                      current: dashboard.actualFPS,
                      history: dashboard.fpsHistory,
                      color: fpsColor,
                      maxY: Double(store.renderFPS) * 1.2,
                      targetLine: Double(store.renderFPS))

            miniChart(title: "Messages", unit: "/s",
                      current: dashboard.messageRate,
                      history: dashboard.msgHistory,
                      color: .orange, maxY: nil)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
    }

    private func miniChart(
        title: String,
        unit: String,
        current: Double,
        history: [Double],
        color: Color,
        maxY: Double?,
        targetLine: Double? = nil
    ) -> some View {
        let data = history.enumerated().map { PanelChartPoint(index: $0.offset, value: $0.element) }
        let yMax = maxY ?? max((history.max() ?? 1) * 1.25, 1)

        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: current >= 1000 ? "%.0f" : "%.1f", current))
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(color)
                Text(unit)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Chart {
                ForEach(data) { pt in
                    AreaMark(x: .value("t", pt.index), y: .value(title, pt.value))
                        .foregroundStyle(color.opacity(0.15))
                    LineMark(x: .value("t", pt.index), y: .value(title, pt.value))
                        .foregroundStyle(color)
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                }
                if let target = targetLine, !data.isEmpty {
                    RuleMark(y: .value("Target", target))
                        .foregroundStyle(Color.secondary.opacity(0.45))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .annotation(position: .trailing) {
                            Text("target").font(.system(size: 7)).foregroundStyle(.secondary)
                        }
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartYScale(domain: 0...yMax)
            .frame(height: 60)
        }
        .padding(10)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Quick Throttle Controls

    private var quickControls: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Quick Controls", systemImage: "slider.horizontal.3")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if isDirty {
                    HStack(spacing: 8) {
                        Button("Discard") { draft = store.snapshot() }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .buttonStyle(.plain)
                        Button("Save") { saveDraft() }
                            .font(.caption.weight(.semibold))
                            .buttonStyle(.borderedProminent)
                            .controlSize(.mini)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            if isDirty {
                Label("Unsaved", systemImage: "clock.badge.exclamationmark")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
            }

            VStack(spacing: 0) {
                quickRow(label: "Preset") {
                    HStack(spacing: 6) {
                        ForEach([PerformanceStore.Preset.eco, .balanced, .performance]) { p in
                            Button {
                                store.applyPreset(p)
                                draft = store.snapshot()
                            } label: {
                                HStack(spacing: 3) {
                                    Image(systemName: p.icon).font(.caption2)
                                    Text(p.label).font(.caption2)
                                }
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(
                                    store.preset == p
                                        ? presetColor(p).opacity(0.2)
                                        : Color.primary.opacity(0.05),
                                    in: Capsule()
                                )
                                .overlay(Capsule().stroke(
                                    store.preset == p ? presetColor(p) : Color.clear,
                                    lineWidth: 1))
                                .foregroundStyle(store.preset == p ? presetColor(p) : .secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Divider().padding(.leading, 16)

                quickRow(label: "Resolution") {
                    Picker("", selection: Binding(get: { draft.renderResolution },
                                                  set: { draft.renderResolution = $0 })) {
                        Text("½").tag(0.5)
                        Text("¾").tag(0.75)
                        Text("Full").tag(1.0)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 120)
                }

                Divider().padding(.leading, 16)

                quickRow(label: "Frame Rate") {
                    Picker("", selection: Binding(get: { draft.renderFPS },
                                                  set: { draft.renderFPS = $0 })) {
                        Text("30 fps").tag(30)
                        Text("60 fps").tag(60)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 140)
                }

                Divider().padding(.leading, 16)

                quickRow(label: "Point Cloud LOD",
                         detail: draft.lodThreshold >= 1_000_000
                             ? String(format: "%.1fM", Double(draft.lodThreshold) / 1_000_000)
                             : "\(draft.lodThreshold / 1000)K") {
                    Slider(value: Binding(
                        get: { Double(draft.lodThreshold) },
                        set: { draft.lodThreshold = Int($0) }),
                           in: 100_000...1_500_000, step: 100_000)
                        .frame(maxWidth: 160)
                }

                Divider().padding(.leading, 16)

                quickRow(label: "Bridge Rate") {
                    Picker("", selection: Binding(get: { draft.subscribeThrottleMs },
                                                  set: { draft.subscribeThrottleMs = $0 })) {
                        Text("Off").tag(0)
                        Text("10 Hz").tag(100)
                        Text("2 Hz").tag(500)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 160)
                }

                Divider().padding(.leading, 16)

                quickRow(label: "Inspector Rate") {
                    Picker("", selection: Binding(get: { draft.inspectorThrottleSeconds },
                                                  set: { draft.inspectorThrottleSeconds = $0 })) {
                        Text("Live").tag(0.0)
                        Text("10 Hz").tag(0.1)
                        Text("2 Hz").tag(0.5)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 160)
                }
            }
            .padding(.bottom, 12)
        }
    }

    // MARK: - Helpers

    private func quickRow<C: View>(
        label: String,
        detail: String? = nil,
        @ViewBuilder control: () -> C
    ) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.caption)
                if let d = detail {
                    Text(d)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(Color.ros2Accent)
                }
            }
            Spacer()
            control()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
    }

    private func statusChip(value: String, icon: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.caption2)
            Text(value).font(.caption.monospacedDigit())
        }
        .foregroundStyle(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.1), in: Capsule())
    }

    private func presetColor(_ p: PerformanceStore.Preset) -> Color {
        switch p {
        case .eco:         return .ros2Accent
        case .balanced:    return .secondary
        case .performance: return .yellow
        case .custom:      return .orange
        }
    }

    private var cpuColor: Color {
        switch dashboard.cpuPercent {
        case ..<50: return .ros2Accent
        case ..<80: return .orange
        default:    return .red
        }
    }

    private var fpsColor: Color {
        guard dashboard.actualFPS > 1 else { return .secondary }
        return dashboard.actualFPS >= Double(store.renderFPS) * 0.85 ? .green : .orange
    }

    private var memShort: String {
        let mb = dashboard.memoryMB
        return mb < 1024 ? String(format: "%.0fMB", mb) : String(format: "%.1fGB", mb / 1024)
    }

    private var fpsShort: String {
        dashboard.actualFPS < 1
            ? "\(store.renderFPS)fps"
            : String(format: "%.0f/\(store.renderFPS)fps", dashboard.actualFPS)
    }

    private func saveDraft() {
        let summary = store.commitDraft(draft)
        draft = store.snapshot()
        services.toasts.show(
            .success,
            title: "Settings saved",
            message: summary.highlights.joined(separator: " · ")
        )
        if summary.tier2Changed && isConnected {
            services.toasts.show(.info, title: "Reconnect to apply buffer & bridge changes")
        }
    }

    private struct PanelChartPoint: Identifiable {
        let id: Int
        let index: Int
        let value: Double
        init(index: Int, value: Double) { id = index; self.index = index; self.value = value }
    }
}
