import Foundation
@preconcurrency import SwiftCBOR
import Logging

/// CBOR codec via SwiftCBOR.
///
/// foxglove_bridge uses CBOR for its binary protocol, including CBOR tag 1
/// for timestamp values. Standard `Codable` round-trips work here; extended
/// tagged-value parsing for raw foxglove frames is handled in M3 Transport.
public struct CBORCodec: Codec {
    public let contentType = "application/cbor"
    private let logger = Logger(subsystem: "app.ros2studio", category: "serialization.cbor")

    public init() {}

    public func encode<T: Encodable>(_ value: T) throws -> Data {
        do {
            return try CodableCBOREncoder().encode(value)
        } catch {
            let reason = String(describing: error)
            logger.error("CBOR encode failed", fields: [LogField(key: "error", value: reason)])
            throw SerializationError.malformedData(reason: reason)
        }
    }

    public func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        // dateStrategy: .taggedAsEpochTimestamp handles foxglove_bridge CBOR tag-1 timestamps
        do {
            return try CodableCBORDecoder().decode(type, from: data)
        } catch let error as DecodingError {
            let reason = decodingErrorReason(error)
            logger.error("CBOR decode failed", fields: [
                LogField(key: "type", value: String(describing: type)),
                LogField(key: "error", value: reason),
            ])
            if case .typeMismatch = error {
                throw SerializationError.schemaMismatch(
                    expected: String(describing: type), actual: "mismatched CBOR type"
                )
            }
            throw SerializationError.malformedData(reason: reason)
        } catch {
            let reason = String(describing: error)
            logger.error("CBOR decode failed", fields: [LogField(key: "error", value: reason)])
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
