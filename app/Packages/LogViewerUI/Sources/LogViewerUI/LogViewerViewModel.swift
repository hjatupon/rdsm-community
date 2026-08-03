import Foundation
import LogStore

public enum TimeRangePreset: String, CaseIterable, Sendable {
    case all = "All"
    case last1m = "1 min"
    case last5m = "5 min"
    case last15m = "15 min"
    case last30m = "30 min"
    case last1h = "1 hr"
    case last6h = "6 hr"
}

@MainActor
@Observable
final class LogViewerViewModel {
    var entries: [LogEntry] = []
    var filteredEntries: [LogEntry] = []
    var enabledSeverities: Set<LogSeverity> = Set(LogSeverity.allCases)
    var nodeFilter: String = ""
    var messageFilter: String = ""
    var regexEnabled: Bool = false
    var caseSensitive: Bool = false
    var timePreset: TimeRangePreset = .all
    var highlightPattern: String = ""
    var maxEntries: Int = 1000
    var fontSize: Int = 11
    var wrapLines: Bool = false
    var autoScroll: Bool = true
    var newestAtTop: Bool = false
    var bookmarkedIDs: Set<UUID> = []
    var expandedIDs: Set<UUID> = []
    var severityCounts: [LogSeverity: Int] = [:]

    private let store: LogStore
    private var streamTask: Task<Void, Never>?

    init(store: LogStore) {
        self.store = store
    }

    func start(maxEntries: Int = 1000) async {
        self.maxEntries = maxEntries
        let snap = await store.snapshot()
        entries = Array(snap.reversed())
        trimToCapIfNeeded()
        applyFilter()
        streamTask?.cancel()
        streamTask = Task { [weak self] in
            guard let self else { return }
            let stream = await self.store.stream()
            for await entry in stream {
                self.append(entry)
            }
        }
    }

    func setMaxEntries(_ newMax: Int) {
        self.maxEntries = newMax
        trimToCapIfNeeded()
        applyFilter()
    }

    func stop() {
        streamTask?.cancel()
        streamTask = nil
    }

    func clearLocal() {
        entries.removeAll()
        filteredEntries.removeAll()
        severityCounts = [:]
    }

    func toggleSeverity(_ sev: LogSeverity) {
        if enabledSeverities.contains(sev) {
            if enabledSeverities.count > 1 {
                enabledSeverities.remove(sev)
            }
        } else {
            enabledSeverities.insert(sev)
        }
        applyFilter()
    }

    func setSeverityOnly(_ sev: LogSeverity) {
        enabledSeverities = [sev]
        applyFilter()
    }

    func enableAllSeverities() {
        enabledSeverities = Set(LogSeverity.allCases)
        applyFilter()
    }

    func applyFilter() {
        filteredEntries = entries.filter { matchesFilter($0) }
        updateSeverityCounts()
    }

    func toggleBookmark(_ id: UUID) {
        if bookmarkedIDs.contains(id) {
            bookmarkedIDs.remove(id)
        } else {
            bookmarkedIDs.insert(id)
        }
    }

    func toggleExpanded(_ id: UUID) {
        if expandedIDs.contains(id) {
            expandedIDs.remove(id)
        } else {
            expandedIDs.insert(id)
        }
    }

    func exportText() -> String {
        filteredEntries.map { entry in
            let ts = timeString(from: entry.timestampNs)
            return "\(ts) [\(entry.severity.label)] [\(entry.node)] \(entry.message)"
        }.joined(separator: "\n")
    }

    func exportJSON() -> Data? {
        let dicts: [[String: Any]] = filteredEntries.map { entry in
            [
                "timestamp": timeString(from: entry.timestampNs),
                "timestampNs": entry.timestampNs,
                "severity": entry.severity.label,
                "node": entry.node,
                "message": entry.message,
                "file": entry.file,
                "function": entry.function,
                "line": entry.line,
            ]
        }
        return try? JSONSerialization.data(withJSONObject: dicts, options: [.prettyPrinted, .sortedKeys])
    }

    func exportCSV() -> String {
        let header = "timestamp,severity,node,message,file,function,line"
        let rows = filteredEntries.map { entry in
            let ts = timeString(from: entry.timestampNs)
            let msg = entry.message.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(ts)\",\"\(entry.severity.label)\",\"\(entry.node)\",\"\(msg)\",\"\(entry.file)\",\"\(entry.function)\",\"\(entry.line)\""
        }
        return ([header] + rows).joined(separator: "\n")
    }

    var allSeverityCounts: [LogSeverity: Int] {
        var counts: [LogSeverity: Int] = [:]
        for sev in LogSeverity.allCases {
            counts[sev] = entries.filter { $0.severity == sev }.count
        }
        return counts
    }

    // MARK: - Private

    private func updateSeverityCounts() {
        var counts: [LogSeverity: Int] = [:]
        for sev in LogSeverity.allCases {
            counts[sev] = filteredEntries.filter { $0.severity == sev }.count
        }
        severityCounts = counts
    }

    private func trimToCapIfNeeded() {
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
    }

    private func append(_ entry: LogEntry) {
        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
        if matchesFilter(entry) {
            filteredEntries.append(entry)
            if filteredEntries.count > maxEntries {
                filteredEntries.removeFirst(filteredEntries.count - maxEntries)
            }
            severityCounts[entry.severity, default: 0] += 1
        }
    }

    private func matchesFilter(_ entry: LogEntry) -> Bool {
        if !enabledSeverities.contains(entry.severity) { return false }

        if !nodeFilter.isEmpty {
            let matchesNode = caseSensitive
                ? entry.node.contains(nodeFilter)
                : entry.node.localizedCaseInsensitiveContains(nodeFilter)
            if !matchesNode { return false }
        }

        let searchText = regexEnabled ? "" : messageFilter
        if !searchText.isEmpty {
            let matchesMsg = caseSensitive
                ? entry.message.contains(searchText)
                : entry.message.localizedCaseInsensitiveContains(searchText)
            if !matchesMsg { return false }
        }

        let regexText = regexEnabled ? messageFilter : ""
        if !regexText.isEmpty {
            let options: NSString.CompareOptions = caseSensitive
                ? .regularExpression
                : [.regularExpression, .caseInsensitive]
            if entry.message.range(of: regexText, options: options) == nil { return false }
        }

        if timePreset != .all {
            let nowNs = UInt64(Date.now.timeIntervalSince1970 * 1_000_000_000)
            let cutoff: UInt64
            switch timePreset {
            case .last1m: cutoff = nowNs - 60_000_000_000
            case .last5m: cutoff = nowNs - 300_000_000_000
            case .last15m: cutoff = nowNs - 900_000_000_000
            case .last30m: cutoff = nowNs - 1_800_000_000_000
            case .last1h: cutoff = nowNs - 3_600_000_000_000
            case .last6h: cutoff = nowNs - 21_600_000_000_000
            case .all: cutoff = 0
            }
            if entry.timestampNs < cutoff { return false }
        }

        return true
    }
}

func timeString(from ns: UInt64) -> String {
    let sec = Double(ns) / 1_000_000_000.0
    let date = Date(timeIntervalSince1970: sec)
    let f = DateFormatter()
    f.dateFormat = "HH:mm:ss.SSS"
    return f.string(from: date)
}
