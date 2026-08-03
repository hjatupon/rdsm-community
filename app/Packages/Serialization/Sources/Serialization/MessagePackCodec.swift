import Foundation
@preconcurrency import MessagePacker
import Logging

/// MessagePack codec via MessagePack.swift.
///
/// Used as a fallback for ROS2 RTPS encapsulation and where compact binary
/// encoding is preferred over CBOR.
public struct MessagePackCodec: Codec {
    public let contentType = "application/msgpack"
    private let logger = Logger(subsystem: "app.ros2studio", category: "serialization.msgpack")

    public init() {}

    public func encode<T: Encodable>(_ value: T) throws -> Data {
        do {
            return try MessagePackEncoder().encode(value)
        } catch {
            let reason = String(describing: error)
            logger.error("MessagePack encode failed", fields: [LogField(key: "error", value: reason)])
            throw SerializationError.malformedData(reason: reason)
        }
    }

    public func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try MessagePackDecoder().decode(type, from: data)
        } catch let error as DecodingError {
            let reason = String(describing: error)
            logger.error("MessagePack decode failed", fields: [
                LogField(key: "type", value: String(describing: type)),
                LogField(key: "error", value: reason),
            ])
            if case .typeMismatch = error {
                throw SerializationError.schemaMismatch(
                    expected: String(describing: type), actual: "mismatched MessagePack type"
                )
            }
            throw SerializationError.malformedData(reason: reason)
        } catch {
            let reason = String(describing: error)
            logger.error("MessagePack decode failed", fields: [LogField(key: "error", value: reason)])
            throw SerializationError.malformedData(reason: reason)
        }
    }
}
