import Foundation
import Metal
import Darwin
import TopicStore

/// Polls system metrics every 0.5 s and exposes live scalars + 60-second history
/// rings to the performance footer bar and monitoring panel.
@Observable @MainActor
final class PerformanceDashboard {

    // MARK: - Live scalars

    private(set) var cpuPercent: Double = 0
    private(set) var memoryMB: Double = 0
    private(set) var actualFPS: Double = 0
    private(set) var messageRate: Double = 0
    private(set) var topicCount: Int = 0
    private(set) var isLowPower: Bool = false

    // MARK: - Static system info

    let totalMemoryGB: Double
    let processorCount: Int
    let gpuName: String

    // MARK: - History rings (120 samples ≈ 60 s at 2 Hz)

    private(set) var cpuHistory: [Double] = []
    private(set) var memHistory: [Double] = []
    private(set) var fpsHistory: [Double] = []
    private(set) var msgHistory: [Double] = []

    // MARK: - Frame counter (nonisolated so PointCloudMetalView can call it directly)

    nonisolated(unsafe) private var _frameCount: Int = 0

    nonisolated func recordFrame() { _frameCount += 1 }

    // MARK: - Wiring

    weak var services: AppServices?

    // MARK: - Internal state

    private var timer: Timer?
    private var lastWall: CFAbsoluteTime = 0
    private var lastCPUSeconds: Double = 0
    private var lastFrameCount: Int = 0
    private var lastRxCount: Int = 0

    // MARK: - Init

    init() {
        totalMemoryGB = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
        processorCount = ProcessInfo.processInfo.processorCount
        gpuName = MTLCreateSystemDefaultDevice()?.name ?? "—"
        isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    // MARK: - Lifecycle

    func start() {
        lastWall = CFAbsoluteTimeGetCurrent()
        lastCPUSeconds = cpuSnapshot().cpuSeconds
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.tick() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Polling

    private func tick() async {
        let now = CFAbsoluteTimeGetCurrent()
        let elapsed = max(now - lastWall, 0.001)
        lastWall = now

        let snap = cpuSnapshot()
        cpuPercent = min(100, (snap.cpuSeconds - lastCPUSeconds) / elapsed * 100)
        lastCPUSeconds = snap.cpuSeconds
        memoryMB = Double(snap.residentBytes) / 1_048_576

        let fc = _frameCount
        actualFPS = min(120, Double(fc - lastFrameCount) / elapsed)
        lastFrameCount = fc

        if let store = services?.activeTopicStore {
            let rxc = await store.totalReceived
            let delta = rxc - lastRxCount
            messageRate = delta > 0 ? Double(delta) / elapsed : 0
            lastRxCount = rxc
        } else {
            messageRate = 0
            lastRxCount = 0
        }
        topicCount = services?.availableTopics.count ?? 0
        isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

        appendAndTrim(&cpuHistory, cpuPercent)
        appendAndTrim(&memHistory, memoryMB)
        appendAndTrim(&fpsHistory, actualFPS)
        appendAndTrim(&msgHistory, messageRate)
    }

    // MARK: - Helpers

    private struct CPUSnapshot {
        var cpuSeconds: Double
        var residentBytes: UInt64
    }

    private func cpuSnapshot() -> CPUSnapshot {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
        withUnsafeMutablePointer(to: &info) { infoPtr in
            infoPtr.withMemoryRebound(to: integer_t.self, capacity: 1) { ptr in
                _ = task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), ptr, &count)
            }
        }
        let cpu = Double(info.user_time.seconds) + Double(info.user_time.microseconds) / 1_000_000
                + Double(info.system_time.seconds) + Double(info.system_time.microseconds) / 1_000_000
        return CPUSnapshot(cpuSeconds: cpu, residentBytes: info.resident_size)
    }

    private func appendAndTrim(_ arr: inout [Double], _ value: Double) {
        arr.append(value)
        if arr.count > 120 { arr.removeFirst(arr.count - 120) }
    }
}
