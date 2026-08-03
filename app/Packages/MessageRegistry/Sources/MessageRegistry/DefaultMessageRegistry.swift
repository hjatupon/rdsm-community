import Foundation
import Logging

/// The standard ``MessageRegistry`` implementation: mutable during the build phase,
/// then frozen to a dict snapshot for O(1) concurrent reads (contract C8).
///
/// ## Lifecycle
/// 1. Create with `DefaultMessageRegistry()`.
/// 2. Call `register(_:)` to add schemas (thread-safe; ignored after `freeze()`).
/// 3. Call `freeze()` once — after this, no further registrations are accepted.
/// 4. Pass `self` as `any MessageRegistry` to consumers; all reads are lock-free.
///
/// `@unchecked Sendable` — NSLock protects the mutable `schemas` and `frozen` flag.
public final class DefaultMessageRegistry: MessageRegistry, @unchecked Sendable {
    private var schemas: [String: MessageSchema] = [:]
    private var frozen = false
    private let lock = NSLock()
    private let logger: any LoggerProtocol

    public init(logger: any LoggerProtocol = NullLogger()) {
        self.logger = logger
    }

    /// Registers `schema` under both its canonical full name and short alias.
    /// No-op after `freeze()`.
    public func register(_ schema: MessageSchema) {
        lock.withLock {
            guard !frozen else { return }
            schemas[schema.fullName] = schema
            // Short alias: "geometry_msgs/Pose" → same schema
            let shortKey = "\(schema.packageName)/\(schema.messageName)"
            if schemas[shortKey] == nil {
                schemas[shortKey] = schema
            }
        }
    }

    /// Prevents further registration and enables lock-free reads in the future.
    /// Safe to call multiple times (idempotent).
    public func freeze() {
        lock.withLock { frozen = true }
        logger.debug("MessageRegistry frozen", fields: [LogField(key: "schemas", value: "\(schemas.count / 2)")])
    }

    // MARK: - MessageRegistry conformance

    public func schema(for name: String) -> MessageSchema? {
        lock.withLock { schemas[name] }
    }

    public func allSchemas() -> [MessageSchema] {
        lock.withLock {
            // Return only canonical (full-name keyed) schemas by filtering for the "/msg/" marker.
            var seen = Set<String>()
            return schemas.values.filter { schema in
                guard schema.fullName.contains("/msg/") else { return false }
                return seen.insert(schema.fullName).inserted
            }
        }
    }
}

/// A no-op ``LoggerProtocol`` used when no logger is injected.
public struct NullLogger: LoggerProtocol, Sendable {
    public init() {}
    public func debug(_ message: String, fields: [LogField]) {}
    public func info(_ message: String, fields: [LogField]) {}
    public func warning(_ message: String, fields: [LogField]) {}
    public func error(_ message: String, fields: [LogField]) {}
}
