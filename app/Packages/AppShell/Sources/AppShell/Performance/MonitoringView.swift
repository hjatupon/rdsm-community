import SwiftUI
import Charts

/// Right-panel "Monitor" tab — live sparkline charts and system capability summary.
struct MonitoringView: View {
    @Environment(PerformanceDashboard.self) private var dashboard
    @Environment(PerformanceStore.self) private var store
    @EnvironmentObject private var services: AppServices

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 20) {
                macSpecsSection
                liveMetricsSection
                activeConfigSection
                connectionSection
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Mac Specs

    private var macSpecsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Mac Hardware", icon: "desktopcomputer")
            VStack(spacing: 6) {
                specRow(label: "GPU", value: dashboard.gpuName)
                specRow(label: "CPU Cores", value: "\(dashboard.processorCount)")
                specRow(label: "Total RAM", value: String(format: "%.1f GB", dashboard.totalMemoryGB))
                if dashboard.isLowPower {
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.slash.fill")
                            .font(.caption2)
                        Text("Low Power Mode active")
                            .font(.caption)
                    }
                    .foregroundStyle(Color.orange)
                    .padding(.top, 2)
                }
            }
            .padding(10)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - Live Metrics (charts)

    private var liveMetricsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Live Metrics", icon: "waveform.path.ecg")

            SparklineCard(
                title: "App CPU",
                unit: "%",
                currentValue: dashboard.cpuPercent,
                history: dashboard.cpuHistory,
                color: .ros2Accent,
                maxY: 100
            )

            SparklineCard(
                title: "App Memory",
                unit: "MB",
                currentValue: dashboard.memoryMB,
                history: dashboard.memHistory,
                color: Color.blue,
                maxY: nil
            )

            SparklineCard(
                title: "Render FPS",
                unit: "fps",
                currentValue: dashboard.actualFPS,
                history: dashboard.fpsHistory,
                color: Color.green,
                maxY: Double(store.renderFPS) * 1.1,
                targetLine: Double(store.renderFPS)
            )

            SparklineCard(
                title: "Message Rate",
                unit: "msg/s",
                currentValue: dashboard.messageRate,
                history: dashboard.msgHistory,
                color: Color.orange,
                maxY: nil
            )
        }
    }

    // MARK: - Active Config

    private var activeConfigSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Active Configuration", icon: "slider.horizontal.3")
            VStack(spacing: 4) {
                configRow(label: "Preset", value: "\(store.preset.label)")
                configRow(label: "Render Resolution", value: resolutionLabel)
                configRow(label: "Render FPS", value: "\(store.renderFPS) fps")
                configRow(label: "Point Cloud LOD", value: lodLabel)
                configRow(label: "Inspector Rate", value: inspectorLabel)
                configRow(label: "Bridge Throttle", value: bridgeLabel)
                configRow(label: "TF History", value: "\(Int(store.tfHistoryDurationSec)) s")
                configRow(label: "Message Buffer", value: "\(store.topicBufferSize) msgs")
                configRow(label: "Topic Cache", value: "\(store.topicCacheCapacity) msgs/topic")
                configRow(label: "Log History", value: "\(store.logCapacity) entries")
                configRow(label: "Chart History", value: "\(store.chartHistoryPoints) pts")
                configRow(label: "Reconnect Attempts", value: "\(store.maxReconnectAttempts)×")
            }
            .padding(10)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - Connection Info

    private var connectionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Session", icon: "network")
            VStack(spacing: 4) {
                configRow(label: "Mode", value: services.sessionMode == .live ? "Live" : "Replay")
                configRow(label: "Connections", value: "\(services.activeConnectionHandles.count)")
                configRow(label: "Available Topics", value: "\(services.availableTopics.count)")
                configRow(label: "Available Frames", value: "\(services.availableFrames.count)")
            }
            .padding(10)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.secondary)
    }

    private func specRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(Color.secondary)
            Spacer()
            Text(value)
                .font(.caption.monospacedDigit())
                .foregroundStyle(Color.primary)
        }
    }

    private func configRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption2)
                .foregroundStyle(Color.secondary)
            Spacer()
            Text(value)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(Color.primary)
        }
    }

    private var resolutionLabel: String {
        switch store.renderResolution {
        case 1.0:  return "Full (Retina)"
        case 0.75: return "75%"
        default:   return "50% (Half)"
        }
    }

    private var lodLabel: String {
        store.lodThreshold >= 1_000_000
            ? String(format: "%.1fM pts", Double(store.lodThreshold) / 1_000_000)
            : "\(store.lodThreshold / 1000)K pts"
    }

    private var inspectorLabel: String {
        store.inspectorThrottleSeconds == 0 ? "Live" :
            "\(Int((1.0 / store.inspectorThrottleSeconds).rounded())) Hz"
    }

    private var bridgeLabel: String {
        switch store.subscribeThrottleMs {
        case 0:   return "None"
        case 100: return "10 Hz"
        default:  return "2 Hz"
        }
    }
}

// MARK: - SparklineCard

private struct SparklineCard: View {
    let title: String
    let unit: String
    let currentValue: Double
    let history: [Double]
    let color: Color
    let maxY: Double?
    var targetLine: Double? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.caption.weight(.medium))
                Spacer()
                Text(String(format: "%.1f \(unit)", currentValue))
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(color)
            }
            chartView
                .frame(height: 52)
        }
        .padding(10)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
    }

    private var chartView: some View {
        let data = history.enumerated().map { ChartPoint(index: $0.offset, value: $0.element) }
        return Chart {
            ForEach(data) { point in
                AreaMark(
                    x: .value("t", point.index),
                    y: .value(title, point.value)
                )
                .foregroundStyle(color.opacity(0.15))

                LineMark(
                    x: .value("t", point.index),
                    y: .value(title, point.value)
                )
                .foregroundStyle(color)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
            if let target = targetLine, !data.isEmpty {
                RuleMark(y: .value("Target", target))
                    .foregroundStyle(Color.secondary.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 2)) {
                AxisValueLabel().font(.system(size: 9))
            }
        }
        .chartYScale(domain: 0...(maxY ?? max(history.max() ?? 1, 1) * 1.2))
    }

    private struct ChartPoint: Identifiable {
        let id: Int
        let index: Int
        let value: Double
        init(index: Int, value: Double) {
            self.id = index
            self.index = index
            self.value = value
        }
    }
}
