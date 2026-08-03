import Foundation

public enum LogSeverity: UInt8, Sendable, CaseIterable {
    case debug = 10
    case info = 20
    case warn = 30
    case error = 40
    case fatal = 50

    public var label: String {
        switch self {
        case .debug: return "DEBUG"
        case .info:  return "INFO"
        case .warn:  return "WARN"
        case .error: return "ERROR"
        case .fatal: return "FATAL"
        }
    }

    public init?(name: String) {
        switch name.uppercased() {
        case "DEBUG": self = .debug
        case "INFO":  self = .info
        case "WARN", "WARNING": self = .warn
        case "ERROR": self = .error
        case "FATAL": self = .fatal
        default: return nil
        }
    }

    public init?(raw: UInt8) {
        self.init(rawValue: raw)
    }
}

public struct LogEntry: Sendable, Identifiable {
    public let id: UUID
    public let timestampNs: UInt64
    public let severity: LogSeverity
    public let node: String
    public let message: String
    public let file: String
    public let function: String
    public let line: UInt32

    public init(
        id: UUID = UUID(),
        timestampNs: UInt64,
        severity: LogSeverity,
        node: String,
        message: String,
        file: String = "",
        function: String = "",
        line: UInt32 = 0
    ) {
        self.id = id
        self.timestampNs = timestampNs
        self.severity = severity
        self.node = node
        self.message = message
        self.file = file
        self.function = function
        self.line = line
    }
}

public struct LogFilter: Sendable {
    public var minSeverity: LogSeverity?
    public var severities: Set<LogSeverity>?
    public var node: String?
    public var substring: String?
    public var regex: String?
    public var caseSensitive: Bool = false
    public var timeRange: ClosedRange<UInt64>?

    public init(
        minSeverity: LogSeverity? = nil,
        severities: Set<LogSeverity>? = nil,
        node: String? = nil,
        substring: String? = nil,
        regex: String? = nil,
        caseSensitive: Bool = false,
        timeRange: ClosedRange<UInt64>? = nil
    ) {
        self.minSeverity = minSeverity
        self.severities = severities
        self.node = node
        self.substring = substring
        self.regex = regex
        self.caseSensitive = caseSensitive
        self.timeRange = timeRange
    }

    public func matches(_ entry: LogEntry) -> Bool {
        if let severities, !severities.isEmpty, !severities.contains(entry.severity) { return false }
        if let minSeverity, entry.severity.rawValue < minSeverity.rawValue { return false }
        if let node, !node.isEmpty {
            let nodeMatches = caseSensitive
                ? entry.node.contains(node)
                : entry.node.localizedCaseInsensitiveContains(node)
            if !nodeMatches { return false }
        }
        if let substring, !substring.isEmpty {
            let msgMatches = caseSensitive
                ? entry.message.contains(substring)
                : entry.message.localizedCaseInsensitiveContains(substring)
            if !msgMatches { return false }
        }
        if let regex, !regex.isEmpty {
            let options: NSString.CompareOptions = caseSensitive
                ? .regularExpression
                : [.regularExpression, .caseInsensitive]
            if entry.message.range(of: regex, options: options) == nil { return false }
        }
        if let timeRange, !timeRange.contains(entry.timestampNs) { return false }
        return true
    }
}
