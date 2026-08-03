import SwiftUI

/// Settings tab for adjusting app performance presets and individual knobs.
/// Preset cards apply immediately; advanced knob changes stage as a draft
/// and require an explicit Save to take effect.
struct PerformanceSettingsTab: View {
    @Environment(PerformanceStore.self) private var store
    @EnvironmentObject private var services: AppServices
    @State private var showAdvanced = false
    @State private var draft = PerformanceStore.DraftValues(
        lodThreshold: 500_000, renderFPS: 60, renderResolution: 0.75,
        inspectorThrottleSeconds: 0.0, topicBufferSize: 256,
        topicCacheCapacity: 1024, logCapacity: 5_000, tfHistoryDurationSec: 10.0,
        maxReconnectAttempts: 10, subscribeThrottleMs: 100, chartHistoryPoints: 2000
    )

    private var isConnected: Bool { !services.activeConnectionHandles.isEmpty }
    private var isDirty: Bool { draft != store.snapshot() }

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 20) {
                presetSection
                Divider()
                advancedToggle
                if showAdvanced {
                    advancedSection
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { draft = store.snapshot() }
        .onChange(of: store.preset) { _, _ in
            // Preset card tap immediately updated the store — sync draft
            draft = store.snapshot()
        }
    }

    // MARK: - Preset cards

    private var presetSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Performance Preset")
                .font(.headline)
            HStack(spacing: 10) {
                ForEach([PerformanceStore.Preset.eco, .balanced, .performance]) { p in
                    PresetCard(preset: p, isSelected: store.preset == p) {
                        store.applyPreset(p)
                        draft = store.snapshot()
                    }
                }
            }
            if store.preset == .custom {
                Label("Custom — individual settings below", systemImage: "slider.horizontal.3")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Advanced toggle

    private var advancedToggle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { showAdvanced.toggle() }
        } label: {
            HStack {
                Label("Advanced Settings", systemImage: "slider.horizontal.3")
                    .font(.callout.weight(.medium))
                if isDirty {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 6))
                        .foregroundStyle(Color.orange)
                }
                Spacer()
                Image(systemName: showAdvanced ? "chevron.up" : "chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Advanced knobs

    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: 14) {

            if isDirty {
                Label("Unsaved changes — click Save to apply", systemImage: "clock.badge.exclamationmark")
                    .font(.caption)
                    .foregroundStyle(Color.orange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 6))
            }

            tierLabel(title: "Live (takes effect immediately)", icon: "bolt.fill",
                      color: Color.ros2Accent)

            renderResolutionRow
            lodRow
            fpsRow
            inspectorThrottleRow

            tierLabel(
                title: isConnected ? "Applies after reconnecting" : "Buffer & Network settings",
                icon: isConnected ? "arrow.trianglehead.clockwise" : "memorychip",
                color: isConnected ? Color.orange : Color.secondary
            )
            .padding(.top, 4)

            subscribeThrottleRow
            bufferRow
            cacheRow
            logRow
            chartHistoryRow
            tfHistoryRow
            reconnectRow

            tierLabel(title: "Smart Throttle", icon: "wand.and.stars", color: Color.secondary)
                .padding(.top, 4)

            autoEcoRow

            if isDirty {
                saveDiscardRow
            }
        }
    }

    // MARK: - Save / Discard

    private var saveDiscardRow: some View {
        HStack(spacing: 10) {
            Button("Discard") {
                draft = store.snapshot()
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.secondary)

            Button("Save") {
                let summary = store.commitDraft(draft)
                draft = store.snapshot()
                services.toasts.show(
                    .success,
                    title: "Performance settings saved",
                    message: summary.highlights.joined(separator: " · ")
                )
                if summary.tier2Changed && isConnected {
                    services.toasts.show(
                        .info,
                        title: "Reconnect to apply buffer & bridge changes"
                    )
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.top, 4)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    // MARK: - Knob rows (all write to draft)

    private var renderResolutionRow: some View {
        let binding = Binding<Double>(
            get: { draft.renderResolution },
            set: { draft.renderResolution = $0 }
        )
        let detail: String
        switch draft.renderResolution {
        case 1.0:  detail = "Full (Retina)"
        case 0.75: detail = "75%"
        default:   detail = "50% (Half)"
        }
        return knobRow(
            label: "Render Resolution",
            detail: detail,
            help: "Metal drawable pixel density. Half = 4× fewer GPU pixels on Retina Macs — big win for old hardware."
        ) {
            Picker("", selection: binding) {
                Text("½").tag(0.5)
                Text("¾").tag(0.75)
                Text("Full").tag(1.0)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 140)
        }
    }

    private var lodRow: some View {
        let binding = Binding<Double>(
            get: { Double(draft.lodThreshold) },
            set: { draft.lodThreshold = Int($0) }
        )
        return knobRow(
            label: "Point Cloud Resolution",
            detail: formatLOD(draft.lodThreshold),
            help: "Max points rendered before stride-decimation. Lower = faster GPU."
        ) {
            Slider(value: binding, in: 100_000...1_500_000, step: 100_000)
        }
    }

    private var fpsRow: some View {
        let binding = Binding<Int>(
            get: { draft.renderFPS },
            set: { draft.renderFPS = $0 }
        )
        return knobRow(
            label: "Render Frame Rate",
            detail: "\(draft.renderFPS) fps",
            help: "Metal viewport target FPS. 30 fps saves GPU and battery on laptops."
        ) {
            Picker("", selection: binding) {
                Text("30 fps").tag(30)
                Text("60 fps").tag(60)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 140)
        }
    }

    private var inspectorThrottleRow: some View {
        let binding = Binding<Double>(
            get: { draft.inspectorThrottleSeconds },
            set: { draft.inspectorThrottleSeconds = $0 }
        )
        let detail: String = draft.inspectorThrottleSeconds == 0
            ? "Live"
            : "\(Int((1.0 / draft.inspectorThrottleSeconds).rounded())) Hz"
        return knobRow(
            label: "Inspector Update Rate",
            detail: detail,
            help: "How often the Inspector panel decodes and redraws messages. Throttle high-Hz topics to reduce CPU."
        ) {
            Picker("", selection: binding) {
                Text("Live").tag(0.0)
                Text("10 Hz").tag(0.1)
                Text("5 Hz").tag(0.2)
                Text("2 Hz").tag(0.5)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 200)
        }
    }

    private var subscribeThrottleRow: some View {
        let binding = Binding<Int>(
            get: { draft.subscribeThrottleMs },
            set: { draft.subscribeThrottleMs = $0 }
        )
        let detail: String
        switch draft.subscribeThrottleMs {
        case 0:   detail = "None"
        case 100: detail = "10 Hz"
        default:  detail = "2 Hz"
        }
        return knobRow(
            label: "Bridge Message Rate",
            detail: detail,
            help: "Asks rosbridge to throttle each topic's publish rate. Reduces network traffic and JSON decode CPU."
        ) {
            Picker("", selection: binding) {
                Text("None").tag(0)
                Text("10 Hz").tag(100)
                Text("2 Hz").tag(500)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 180)
        }
    }

    private var bufferRow: some View {
        let binding = Binding<Double>(
            get: { Double(draft.topicBufferSize) },
            set: { draft.topicBufferSize = Int($0) }
        )
        return knobRow(
            label: "Message Buffer",
            detail: "\(draft.topicBufferSize) msgs",
            help: "Per-topic rosbridge ring buffer. Smaller drops older messages sooner under load."
        ) {
            Slider(value: binding, in: 64...1024, step: 64)
        }
    }

    private var cacheRow: some View {
        let binding = Binding<Double>(
            get: { Double(draft.topicCacheCapacity) },
            set: { draft.topicCacheCapacity = Int($0) }
        )
        return knobRow(
            label: "Topic Cache",
            detail: "\(draft.topicCacheCapacity) msgs/topic",
            help: "TopicStore ring buffer per topic. Smaller reduces RAM usage."
        ) {
            Slider(value: binding, in: 256...4096, step: 256)
        }
    }

    private var logRow: some View {
        let binding = Binding<Double>(
            get: { Double(draft.logCapacity) },
            set: { draft.logCapacity = Int($0) }
        )
        return knobRow(
            label: "Log History",
            detail: "\(draft.logCapacity) entries",
            help: "Maximum /rosout entries kept in the log panel. Smaller uses less RAM."
        ) {
            Slider(value: binding, in: 1000...20000, step: 1000)
        }
    }

    private var chartHistoryRow: some View {
        let binding = Binding<Int>(
            get: { draft.chartHistoryPoints },
            set: { draft.chartHistoryPoints = $0 }
        )
        return knobRow(
            label: "Chart History",
            detail: "\(draft.chartHistoryPoints) pts",
            help: "Ring-buffer size for numeric charts in the Inspector. Smaller uses less RAM. Takes effect next time you open a topic."
        ) {
            Picker("", selection: binding) {
                Text("500").tag(500)
                Text("2 K").tag(2000)
                Text("4 K").tag(4096)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 160)
        }
    }

    private var tfHistoryRow: some View {
        let binding = Binding<Double>(
            get: { draft.tfHistoryDurationSec },
            set: { draft.tfHistoryDurationSec = $0 }
        )
        return knobRow(
            label: "TF History Window",
            detail: "\(Int(draft.tfHistoryDurationSec)) s",
            help: "How many seconds of TF transforms are buffered. Longer smooths slow publishers but uses more RAM."
        ) {
            Picker("", selection: binding) {
                Text("5 s").tag(5.0)
                Text("10 s").tag(10.0)
                Text("30 s").tag(30.0)
                Text("60 s").tag(60.0)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 200)
        }
    }

    private var reconnectRow: some View {
        let binding = Binding<Int>(
            get: { draft.maxReconnectAttempts },
            set: { draft.maxReconnectAttempts = $0 }
        )
        return knobRow(
            label: "Reconnect Attempts",
            detail: "\(draft.maxReconnectAttempts)×",
            help: "How many times the transport retries after losing connection before giving up."
        ) {
            Picker("", selection: binding) {
                Text("3×").tag(3)
                Text("10×").tag(10)
                Text("20×").tag(20)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 160)
        }
    }

    // autoEcoOnBattery applies immediately — not part of draft
    private var autoEcoRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("Auto Eco on Low Power Mode", isOn: Binding(
                get: { store.autoEcoOnBattery },
                set: { store.autoEcoOnBattery = $0 }
            ))
            .toggleStyle(.switch)
            .font(.callout)
            Text("Automatically applies the Eco preset when macOS Low Power Mode is active.")
                .font(.caption2)
                .foregroundStyle(Color.secondary)
        }
    }

    // MARK: - Helpers

    private func tierLabel(title: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.medium))
                .foregroundStyle(color)
            Divider()
        }
    }

    private func knobRow<Control: View>(
        label: String,
        detail: String,
        help: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.callout)
                Spacer()
                Text(detail)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            control().help(help)
        }
    }

    private func formatLOD(_ n: Int) -> String {
        n >= 1_000_000 ? String(format: "%.1fM pts", Double(n) / 1_000_000) : "\(n / 1000)K pts"
    }
}

// MARK: - Preset card

private struct PresetCard: View {
    let preset: PerformanceStore.Preset
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            cardContent
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .help(preset.description)
        .accessibilityLabel(preset.label)
        .accessibilityHint(preset.description)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: preset.icon)
                .font(.title3)
                .foregroundStyle(isSelected ? Color.ros2Accent : Color.secondary)
            Text(preset.label)
                .font(.callout.weight(.semibold))
                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            Text(preset.description)
                .font(.caption2)
                .foregroundStyle(Color.secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(isSelected ? 0.07 : 0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    isSelected ? Color.ros2Accent : Color.secondary.opacity(0.3),
                    lineWidth: isSelected ? 1.5 : 0.5
                )
        )
    }
}
