import Foundation

/// Unified encoding/decoding protocol for all wire formats used by ROS2 Studio.
///
/// All concrete implementations are stateless — a single instance may be shared
/// freely across threads (all conformers are `Sendable`).
public protocol Codec: Sendable {
    /// MIME content type identifying the wire format.
    var contentType: String { get }

    /// Encodes `value` into the codec's wire format.
    func encode<T: Encodable>(_ value: T) throws -> Data

    /// Decodes a `T` from bytes encoded in the codec's wire format.
    func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T
}

// MARK: - Error type

/// All errors surfaced by codec operations.
///
/// Raw library errors are mapped to these cases — no third-party error types
/// ever escape the public API.
public enum SerializationError: Error, Sendable, Equatable {
    case malformedData(reason: String)
    case unsupportedType(String)
    case schemaMismatch(expected: String, actual: String)
}
