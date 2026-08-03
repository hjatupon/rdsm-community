/// Abstraction over the concrete ``Logger`` type, enabling mock injection in tests.
///
/// All methods are non-throwing and non-blocking — callers never need to handle errors.
public protocol LoggerProtocol: Sendable {
    func debug(_ message: String, fields: [LogField])
    func info(_ message: String, fields: [LogField])
    func warning(_ message: String, fields: [LogField])
    func error(_ message: String, fields: [LogField])
}

public extension LoggerProtocol {
    func debug(_ message: String) { debug(message, fields: []) }
    func info(_ message: String) { info(message, fields: []) }
    func warning(_ message: String) { warning(message, fields: []) }
    func error(_ message: String) { error(message, fields: []) }
}
