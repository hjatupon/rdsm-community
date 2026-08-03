import Foundation
import Observation

/// Global performance profile. Owns preset selection + individual knobs.
/// Tier 1 knobs (LOD, FPS) take effect immediately in the render loop.
/// Tier 2 knobs (buffers) are read from UserDefaults on next reconnect.
@Observable @MainActor
final class PerformanceStore {

    enum Preset: String, CaseIterable, Identifiable {
        case eco, balanced, performance, custom
        var id: String { rawValue }

        var label: String {
            switch self {
            case .eco:         return "Eco"
            case .balanced:    return "Balanced"
            case .performance: return "Performance"
            case .custom:      return "Custom"
            }
        }

        var icon: String {
            switch self {
            case .eco:         return "leaf.fill"
            case .balanced:    return "scalemass.fill"
            case .performance: return "bolt.fill"
            case .custom:      return "slider.horizontal.3"
            }
        }

        var description: String {
            switch self {
            case .eco:         return "Optimised for old or low-power Macs. Cuts render resolution, frame rate, point density, bridge rate, and buffer sizes."
            case .balanced:    return "Recommended for most machines. Good quality with moderate CPU, GPU, and RAM usage."
            case .performance: return "Full fidelity for M3 Pro / M4 and later. Native resolution, live data, large buffers, fast reconnect."
            case .custom:      return "Custom configuration."
            }
        }
    }

    // MARK: - Draft (pending changes before Save)

    struct DraftValues: Equatable {
        var lodThreshold: Int
        var renderFPS: Int
        var renderResolution: Double
        var inspectorThrottleSeconds: Double
        var topicBufferSize: Int
        var topicCacheCapacity: Int
        var logCapacity: Int
        var tfHistoryDurationSec: Double
        var maxReconnectAttempts: Int
        var subscribeThrottleMs: Int
        var chartHistoryPoints: Int
    }

    struct CommitSummary {
        let preset: Preset
        let tier2Changed: Bool
        let highlights: [String]
    }

    func snapshot() -> DraftValues {
        DraftValues(
            lodThreshold: lodThreshold,
            renderFPS: renderFPS,
            renderResolution: renderResolution,
            inspectorThrottleSeconds: inspectorThrottleSeconds,
            topicBufferSize: topicBufferSize,
            topicCacheCapacity: topicCacheCapacity,
            logCapacity: logCapacity,
            tfHistoryDurationSec: tfHistoryDurationSec,
            maxReconnectAttempts: maxReconnectAttempts,
            subscribeThrottleMs: subscribeThrottleMs,
            chartHistoryPoints: chartHistoryPoints
        )
    }

    func commitDraft(_ draft: DraftValues) -> CommitSummary {
        let before = snapshot()
        let tier2Changed = before.topicBufferSize     != draft.topicBufferSize
            || before.topicCacheCapacity              != draft.topicCacheCapacity
            || before.logCapacity                     != draft.logCapacity
            || before.maxReconnectAttempts            != draft.maxReconnectAttempts
            || before.subscribeThrottleMs             != draft.subscribeThrottleMs
            || before.chartHistoryPoints              != draft.chartHistoryPoints
            || before.tfHistoryDurationSec            != draft.tfHistoryDurationSec

        lodThreshold             = draft.lodThreshold
        renderFPS                = draft.renderFPS
        renderResolution         = draft.renderResolution
        inspectorThrottleSeconds = draft.inspectorThrottleSeconds
        topicBufferSize          = draft.topicBufferSize
        topicCacheCapacity       = draft.topicCacheCapacity
        logCapacity              = draft.logCapacity
        tfHistoryDurationSec     = draft.tfHistoryDurationSec
        maxReconnectAttempts     = draft.maxReconnectAttempts
        subscribeThrottleMs      = draft.subscribeThrottleMs
        chartHistoryPoints       = draft.chartHistoryPoints

        let matchedPreset = [Preset.eco, .balanced, .performance].first { p in
            guard let pv = Self.presetValues[p] else { return false }
            return presetValues(pv) == draft
        }
        if let p = matchedPreset {
            preset = p
            UserDefaults.standard.set(p.rawValue, forKey: "perf.preset")
        } else {
            markCustom()
        }

        return CommitSummary(preset: preset, tier2Changed: tier2Changed, highlights: highlights(for: draft))
    }

    private func presetValues(_ pv: PresetValues) -> DraftValues {
        DraftValues(
            lodThreshold: pv.lod, renderFPS: pv.fps, renderResolution: pv.renderResolution,
            inspectorThrottleSeconds: pv.inspectorThrottle, topicBufferSize: pv.buffer,
            topicCacheCapacity: pv.cache, logCapacity: pv.log, tfHistoryDurationSec: pv.tfHistory,
            maxReconnectAttempts: pv.reconnect, subscribeThrottleMs: pv.subscribeThrottleMs,
            chartHistoryPoints: pv.chartHistoryPoints
        )
    }

    private func highlights(for d: DraftValues) -> [String] {
        var h: [String] = []
        switch d.renderResolution {
        case 1.0:  h.append("Full res")
        case 0.75: h.append("¾ res")
        default:   h.append("½ res")
        }
        h.append("\(d.renderFPS) fps")
        h.append(d.lodThreshold >= 1_000_000
            ? String(format: "%.1fM pts", Double(d.lodThreshold) / 1_000_000)
            : "\(d.lodThreshold / 1000)K pts")
        if d.subscribeThrottleMs > 0 { h.append("bridge \(d.subscribeThrottleMs)ms") }
        return h
    }

    // MARK: - Preset values

    private struct PresetValues {
        let lod: Int
        let fps: Int
        let buffer: Int
        let cache: Int
        let log: Int
        let inspectorThrottle: Double
        let tfHistory: Double
        let reconnect: Int
        let renderResolution: Double
        let subscribeThrottleMs: Int
        let chartHistoryPoints: Int
    }

    private static let presetValues: [Preset: PresetValues] = [
        .eco:         PresetValues(lod: 200_000,   fps: 30, buffer:   64, cache:   256, log:  1_000, inspectorThrottle: 0.5, tfHistory:  5.0, reconnect:  3, renderResolution: 0.5,  subscribeThrottleMs: 500, chartHistoryPoints:  500),
        .balanced:    PresetValues(lod: 500_000,   fps: 60, buffer:  256, cache: 1_024, log:  5_000, inspectorThrottle: 0.1, tfHistory: 10.0, reconnect: 10, renderResolution: 0.75, subscribeThrottleMs: 100, chartHistoryPoints: 2000),
        .performance: PresetValues(lod: 1_000_000, fps: 60, buffer: 1024, cache: 4_096, log: 20_000, inspectorThrottle: 0.0, tfHistory: 30.0, reconnect: 20, renderResolution: 1.0,  subscribeThrottleMs:   0, chartHistoryPoints: 4096),
    ]

    // MARK: - Knobs (Tier 1 — live)

    /// Max points before the renderer stride-decimates. Smaller = fewer GPU vertices.
    var lodThreshold: Int = 500_000 {
        didSet { saveInt("perf.lodThreshold", lodThreshold) }
    }

    /// Target Metal render frame rate. Lower saves GPU/battery.
    var renderFPS: Int = 60 {
        didSet { saveInt("perf.renderFPS", renderFPS) }
    }

    /// Inspector panel display update interval in seconds. 0 = live (every message).
    /// Written to UserDefaults so InspectorView picks it up via @AppStorage.
    var inspectorThrottleSeconds: Double = 0.0 {
        didSet { saveDouble("perf.inspectorThrottleSeconds", inspectorThrottleSeconds) }
    }

    /// Metal drawable resolution as a fraction of native backing scale.
    /// 1.0 = full Retina; 0.5 = half-resolution (4× fewer GPU pixels on Retina Macs).
    /// Saved to UserDefaults so MainWindow can read it via @AppStorage binding.
    var renderResolution: Double = 0.75 {
        didSet { saveDouble("perf.renderResolution", renderResolution) }
    }

    // MARK: - Knobs (Tier 2 — apply on reconnect)

    /// Per-topic rosbridge message ring-buffer size. Smaller drops older messages sooner.
    var topicBufferSize: Int = 256 {
        didSet { saveInt("perf.topicBufferSize", topicBufferSize) }
    }

    /// TopicStore ring-buffer capacity per topic. Smaller uses less RAM.
    var topicCacheCapacity: Int = 1_024 {
        didSet { saveInt("perf.topicCacheCapacity", topicCacheCapacity) }
    }

    /// LogStore entry limit (rolling window). Smaller keeps less /rosout history.
    var logCapacity: Int = 5_000 {
        didSet { saveInt("perf.logCapacity", logCapacity) }
    }

    /// TF transform history window in seconds. Shorter uses less RAM; longer smooths slow TF publishers.
    var tfHistoryDurationSec: Double = 10.0 {
        didSet { saveDouble("perf.tfHistoryDurationSec", tfHistoryDurationSec) }
    }

    /// How many consecutive reconnect failures the transport tolerates before giving up.
    var maxReconnectAttempts: Int = 10 {
        didSet { saveInt("perf.maxReconnectAttempts", maxReconnectAttempts) }
    }

    /// rosbridge throttle_rate in subscribe ops (ms). 0 = no throttle.
    /// Bridge sends each topic at most once per this interval, reducing network + CPU load.
    var subscribeThrottleMs: Int = 100 {
        didSet { saveInt("perf.subscribeThrottleMs", subscribeThrottleMs) }
    }

    /// Inspector numeric chart ring-buffer capacity (number of data points).
    /// Read from UserDefaults in InspectorViewModel init; takes effect next topic open.
    var chartHistoryPoints: Int = 2000 {
        didSet { saveInt("perf.chartHistoryPoints", chartHistoryPoints) }
    }

    // MARK: - Smart knob (not part of preset)

    /// When true, automatically applies the Eco preset when macOS Low Power Mode is active.
    var autoEcoOnBattery: Bool = false {
        didSet { UserDefaults.standard.set(autoEcoOnBattery, forKey: "perf.autoEcoOnBattery") }
    }

    // MARK: - Preset

    private(set) var preset: Preset = .balanced

    func applyPreset(_ p: Preset) {
        guard p != .custom, let v = Self.presetValues[p] else { return }
        preset = p
        lodThreshold             = v.lod
        renderFPS                = v.fps
        topicBufferSize          = v.buffer
        topicCacheCapacity       = v.cache
        logCapacity              = v.log
        inspectorThrottleSeconds = v.inspectorThrottle
        tfHistoryDurationSec     = v.tfHistory
        maxReconnectAttempts     = v.reconnect
        renderResolution         = v.renderResolution
        subscribeThrottleMs      = v.subscribeThrottleMs
        chartHistoryPoints       = v.chartHistoryPoints
        UserDefaults.standard.set(p.rawValue, forKey: "perf.preset")
    }

    /// Call when any individual knob is changed by the user (not via applyPreset).
    func markCustom() {
        guard preset != .custom else { return }
        preset = .custom
        UserDefaults.standard.set(Preset.custom.rawValue, forKey: "perf.preset")
    }

    // MARK: - Init

    init() {
        let ud = UserDefaults.standard
        func loadInt(_ key: String, default def: Int) -> Int {
            let v = ud.integer(forKey: key); return v > 0 ? v : def
        }
        func loadDouble(_ key: String, default def: Double) -> Double {
            let v = ud.double(forKey: key); return v > 0 ? v : def
        }
        lodThreshold             = loadInt("perf.lodThreshold",          default: 500_000)
        renderFPS                = loadInt("perf.renderFPS",             default: 60)
        topicBufferSize          = loadInt("perf.topicBufferSize",       default: 256)
        topicCacheCapacity       = loadInt("perf.topicCacheCapacity",    default: 1_024)
        logCapacity              = loadInt("perf.logCapacity",           default: 5_000)
        maxReconnectAttempts     = loadInt("perf.maxReconnectAttempts",  default: 10)
        subscribeThrottleMs      = loadInt("perf.subscribeThrottleMs",   default: 100)
        chartHistoryPoints       = loadInt("perf.chartHistoryPoints",    default: 2000)
        inspectorThrottleSeconds = loadDouble("perf.inspectorThrottleSeconds", default: 0.0)
        tfHistoryDurationSec     = loadDouble("perf.tfHistoryDurationSec",     default: 10.0)
        renderResolution         = loadDouble("perf.renderResolution",         default: 0.75)
        autoEcoOnBattery         = ud.bool(forKey: "perf.autoEcoOnBattery")
        preset = Preset(rawValue: ud.string(forKey: "perf.preset") ?? "") ?? .balanced
    }

    // MARK: - Private

    private func saveInt(_ key: String, _ value: Int) {
        UserDefaults.standard.set(value, forKey: key)
    }

    private func saveDouble(_ key: String, _ value: Double) {
        UserDefaults.standard.set(value, forKey: key)
    }
}
