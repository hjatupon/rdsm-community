/// A single structured metadata field attached to a log message.
///
/// Fields with ``redacted`` set to `true` have their value replaced with
/// `<redacted>` before reaching the console, protecting sensitive data.
public struct LogField: Sendable, Equatable {
    public let key: String
    public let value: String
    public let redacted: Bool

    public init(key: String, value: String, redacted: Bool = false) {
        self.key = key
        self.value = value
        self.redacted = redacted
    }

    /// Creates a field whose value is hidden in logs.
    public static func redacted(key: String, value: String) -> LogField {
        LogField(key: key, value: value, redacted: true)
    }

    /// The value written to the log: original if not redacted, `<redacted>` otherwise.
    public var logValue: String {
        redacted ? "<redacted>" : value
    }
}
