/// A single decoded field value, covering all ROS2 primitive types plus nested
/// messages and arrays. The `indirect` case `message` enables recursive structures.
public indirect enum AnyDecodedValue: Sendable {
    case bool(Bool)
    case byte(UInt8), char(UInt8)
    case float32(Float), float64(Double)
    case int8(Int8), int16(Int16), int32(Int32), int64(Int64)
    case uint8(UInt8), uint16(UInt16), uint32(UInt32), uint64(UInt64)
    case string(String)
    case message(AnyDecodedMessage)
    case array([AnyDecodedValue])
    case null  // field present in schema but payload provided no value
}

/// A dynamically-decoded ROS2 message, schema-driven but without compile-time
/// Swift types. Callers look up fields by name; nested messages are themselves
/// `AnyDecodedMessage` values.
///
/// This is the output type of ``DynamicDecoder`` and the "schema-unknown" subscription
/// path in ``TopicStore`` (M12).
public struct AnyDecodedMessage: Sendable {
    /// The full schema name, e.g. `"geometry_msgs/msg/Pose"`.
    public let schemaName: String
    /// Field name → decoded value. Ordered by field declaration order.
    public let fields: [String: AnyDecodedValue]

    public init(schemaName: String, fields: [String: AnyDecodedValue]) {
        self.schemaName = schemaName
        self.fields = fields
    }

    /// Subscript access — `nil` if the field is absent.
    public subscript(field: String) -> AnyDecodedValue? {
        fields[field]
    }
}

extension AnyDecodedValue: CustomStringConvertible {
    public var description: String {
        switch self {
        case .bool(let v): "bool(\(v))"
        case .byte(let v): "byte(\(v))"
        case .char(let v): "char(\(v))"
        case .float32(let v): "float32(\(v))"
        case .float64(let v): "float64(\(v))"
        case .int8(let v): "int8(\(v))"
        case .int16(let v): "int16(\(v))"
        case .int32(let v): "int32(\(v))"
        case .int64(let v): "int64(\(v))"
        case .uint8(let v): "uint8(\(v))"
        case .uint16(let v): "uint16(\(v))"
        case .uint32(let v): "uint32(\(v))"
        case .uint64(let v): "uint64(\(v))"
        case .string(let v): "string(\"\(v)\")"
        case .message(let m): "message(\(m.schemaName))"
        case .array(let a): "array[\(a.count)]"
        case .null: "null"
        }
    }
}
