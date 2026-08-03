import Foundation
import Testing
@testable import Logging

// MARK: - LogField tests

@Suite("LogField")
struct LogFieldTests {
    @Test("non-redacted field returns original value")
    func nonRedactedPassesThrough() {
        let field = LogField(key: "topic", value: "/camera/image")
        #expect(field.logValue == "/camera/image")
    }

    @Test("redacted field replaces value with <redacted>")
    func redactedSubstituted() {
        let field = LogField.redacted(key: "token", value: "secret-abc")
        #expect(field.logValue == "<redacted>")
        #expect(field.key == "token")
    }

    @Test("default redacted flag is false")
    func defaultNotRedacted() {
        let field = LogField(key: "k", value: "v")
        #expect(field.redacted == false)
    }

    @Test("convenience static redacted sets flag to true")
    func convenienceRedactedFlag() {
        let field = LogField.redacted(key: "k", value: "v")
        #expect(field.redacted == true)
    }
}

// MARK: - Logger thread-safety (Sendable / concurrent calls don't crash)

@Suite("Logger concurrency")
struct LoggerConcurrencyTests {
    @Test("concurrent calls from TaskGroup don't crash")
    func concurrentLogging() async {
        let logger = Logger(subsystem: "test.ros2studio", category: "concurrency")
        await withTaskGroup(of: Void.self) { group in
            for i in 0 ..< 100 {
                group.addTask {
                    logger.debug("ping \(i)", fields: [LogField(key: "i", value: "\(i)")])
                }
            }
        }
        // If we reach here without crashing, the contract is satisfied.
    }
}

// MARK: - Logger.shared exists and has correct subsystem

@Suite("Logger.shared")
struct LoggerSharedTests {
    @Test("shared instance is accessible and Sendable")
    func sharedExists() {
        let logger: any LoggerProtocol = Logger.shared
        // Call all four levels to cover level routing
        logger.debug("test debug")
        logger.info("test info")
        logger.warning("test warning")
        logger.error("test error")
    }

    @Test("no-fields convenience methods work")
    func noFieldsConvenience() {
        let logger = Logger(subsystem: "test.ros2studio", category: "convenience")
        logger.info("no fields message")
    }
}

// MARK: - CapturingLogger for behaviour verification

/// In-memory logger that records messages for assertion (doesn't need os.Logger).
final class CapturingLogger: LoggerProtocol, @unchecked Sendable {
    struct Entry: Sendable {
        let level: Level
        let message: String
        let fields: [LogField]
    }
    enum Level { case debug, info, warning, error }

    private let lock = NSLock()
    private(set) var entries: [Entry] = []

    func debug(_ message: String, fields: [LogField]) { append(.debug, message, fields) }
    func info(_ message: String, fields: [LogField]) { append(.info, message, fields) }
    func warning(_ message: String, fields: [LogField]) { append(.warning, message, fields) }
    func error(_ message: String, fields: [LogField]) { append(.error, message, fields) }

    private func append(_ level: Level, _ message: String, _ fields: [LogField]) {
        lock.lock(); defer { lock.unlock() }
        entries.append(Entry(level: level, message: message, fields: fields))
    }
}

@Suite("CapturingLogger — level routing and field redaction")
struct CapturingLoggerTests {
    @Test("each method routes to the correct level")
    func levelRouting() {
        let log = CapturingLogger()
        log.debug("d", fields: [])
        log.info("i", fields: [])
        log.warning("w", fields: [])
        log.error("e", fields: [])
        #expect(log.entries[0].level == .debug)
        #expect(log.entries[1].level == .info)
        #expect(log.entries[2].level == .warning)
        #expect(log.entries[3].level == .error)
    }

    @Test("redacted field value is hidden in logValue")
    func redactionInField() {
        let log = CapturingLogger()
        let secret = LogField.redacted(key: "password", value: "hunter2")
        log.info("auth attempt", fields: [secret])
        let entry = log.entries[0]
        #expect(entry.fields[0].logValue == "<redacted>")
        #expect(entry.fields[0].key == "password")
    }

    @Test("non-redacted field value passes through in logValue")
    func nonRedactedField() {
        let log = CapturingLogger()
        log.info("connect", fields: [LogField(key: "url", value: "ws://localhost:8765")])
        #expect(log.entries[0].fields[0].logValue == "ws://localhost:8765")
    }

    @Test("message is stored verbatim")
    func messageVerbatim() {
        let log = CapturingLogger()
        log.warning("connection lost", fields: [])
        #expect(log.entries[0].message == "connection lost")
    }
}
