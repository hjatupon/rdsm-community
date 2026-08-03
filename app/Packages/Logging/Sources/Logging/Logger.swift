import os

/// Structured logger wrapping `os.Logger`.
///
/// Create one per subsystem/category pair; use ``Logger/shared`` as the app-wide default.
/// Every call is thread-safe, non-throwing, and non-blocking.
///
/// Fields with ``LogField/redacted`` set to `true` have their values replaced with
/// `<redacted>` before any data reaches the console.
public struct Logger: LoggerProtocol {
    // os.Logger is NOT in the public interface — callers only see LoggerProtocol.
    private let inner: os.Logger

    /// Creates a logger scoped to the given subsystem and category.
    ///
    /// Visible in Console.app under **subsystem › category**.
    public init(subsystem: String, category: String) {
        inner = os.Logger(subsystem: subsystem, category: category)
    }

    /// App-wide default logger (`subsystem: "app.ros2studio", category: "general"`).
    public static let shared = Logger(subsystem: "app.ros2studio", category: "general")

    // MARK: - LoggerProtocol

    public func debug(_ message: String, fields: [LogField]) {
        inner.debug("\(message, privacy: .public)\(fieldsString(fields))")
    }

    public func info(_ message: String, fields: [LogField]) {
        inner.info("\(message, privacy: .public)\(fieldsString(fields))")
    }

    public func warning(_ message: String, fields: [LogField]) {
        inner.warning("\(message, privacy: .public)\(fieldsString(fields))")
    }

    public func error(_ message: String, fields: [LogField]) {
        inner.error("\(message, privacy: .public)\(fieldsString(fields))")
    }

    // MARK: - Private

    private func fieldsString(_ fields: [LogField]) -> String {
        guard !fields.isEmpty else { return "" }
        let pairs = fields.map { "\($0.key)=\($0.logValue)" }.joined(separator: " ")
        return " [\(pairs)]"
    }
}
