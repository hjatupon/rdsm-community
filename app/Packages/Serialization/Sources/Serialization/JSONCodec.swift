import Foundation
import Logging

/// JSON codec via Foundation `JSONEncoder` / `JSONDecoder`.
///
/// Used for rosbridge v2 protocol, settings files, and layout persistence.
public struct JSONCodec: Codec {
    public let contentType = "application/json"
    public let prettyPrint: Bool
    private let logger = Logger(subsystem: "app.ros2studio", category: "serialization.json")

    public init(prettyPrint: Bool = false) {
        self.prettyPrint = prettyPrint
    }

    public func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        if prettyPrint {
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        }
        do {
            return try encoder.encode(value)
        } catch let error as EncodingError {
            let reason = String(describing: error)
            logger.error("JSON encode failed", fields: [LogField(key: "error", value: reason)])
            throw SerializationError.malformedData(reason: reason)
        } catch {
            let reason = String(describing: error)
            logger.error("JSON encode failed", fields: [LogField(key: "error", value: reason)])
            throw SerializationError.malformedData(reason: reason)
        }
    }

    public func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch let error as DecodingError {
            let reason = decodingErrorReason(error)
            logger.error("JSON decode failed", fields: [
                LogField(key: "type", value: String(describing: type)),
                LogField(key: "error", value: reason),
            ])
            if case .typeMismatch = error {
                throw SerializationError.schemaMismatch(
                    expected: String(describing: type), actual: "mismatched JSON type"
                )
            }
            throw SerializationError.malformedData(reason: reason)
        } catch {
            let reason = String(describing: error)
            logger.error("JSON decode failed", fields: [LogField(key: "error", value: reason)])
            throw SerializationError.malformedData(reason: reason)
        }
    }
}

// MARK: - Private helpers

private func decodingErrorReason(_ error: DecodingError) -> String {
    switch error {
    case .typeMismatch(let type, let ctx):
        return "type mismatch: expected \(type), \(ctx.debugDescription)"
    case .valueNotFound(let type, let ctx):
        return "value not found: \(type), \(ctx.debugDescription)"
    case .keyNotFound(let key, let ctx):
        return "key not found: \(key.stringValue), \(ctx.debugDescription)"
    case .dataCorrupted(let ctx):
        return "data corrupted: \(ctx.debugDescription)"
    @unknown default:
        return String(describing: error)
    }
}
