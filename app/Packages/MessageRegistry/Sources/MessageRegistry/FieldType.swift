import Foundation

/// All field types that can appear in a `.msg` definition.
///
/// Primitive types mirror the ROS2 IDL primitive set. `nested` carries the fully-qualified
/// schema name (e.g. `"geometry_msgs/msg/Point"`). `array` covers both fixed-size (`count != nil`)
/// and unbounded sequences (`count == nil`). `bounded` covers `Type[<=N]`.
public indirect enum FieldType: Sendable, Hashable {
    case bool
    case byte, char
    case float32, float64
    case int8, int16, int32, int64
    case uint8, uint16, uint32, uint64
    case string, wstring
    /// A nested message, e.g. `geometry_msgs/msg/Point` or `Point` (within the same package).
    case nested(schemaName: String)
    /// Fixed-size (`count != nil`) or unbounded (`count == nil`) array.
    case array(FieldType, count: Int?)
    /// Bounded sequence (`Type[<=N]`).
    case bounded(FieldType, maxCount: Int)

    /// `true` if this is a scalar (not an array or bounded).
    public var isScalar: Bool {
        switch self {
        case .array, .bounded: false
        default: true
        }
    }

    /// The element type if this is an array or bounded; `self` otherwise.
    public var elementType: FieldType {
        switch self {
        case .array(let t, _): t
        case .bounded(let t, _): t
        default: self
        }
    }

    /// Canonical string representation matching the .msg syntax.
    public var description: String {
        switch self {
        case .bool: "bool"
        case .byte: "byte"
        case .char: "char"
        case .float32: "float32"
        case .float64: "float64"
        case .int8: "int8"
        case .int16: "int16"
        case .int32: "int32"
        case .int64: "int64"
        case .uint8: "uint8"
        case .uint16: "uint16"
        case .uint32: "uint32"
        case .uint64: "uint64"
        case .string: "string"
        case .wstring: "wstring"
        case .nested(let name): name
        case .array(let t, let c):
            c.map { "\(t.description)[\($0)]" } ?? "\(t.description)[]"
        case .bounded(let t, let max):
            "\(t.description)[<=\(max)]"
        }
    }
}
