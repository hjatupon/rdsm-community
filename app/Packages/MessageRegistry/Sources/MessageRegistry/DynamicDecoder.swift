import Foundation

/// Decodes a raw payload `Data` into an ``AnyDecodedMessage`` using a ``MessageSchema``
/// to drive field-level interpretation.
///
/// ## Supported encodings
/// - **JSON**: `schemaEncoding == "json"` — uses `JSONSerialization`. Schema is used
///   only to map raw JSON values to typed `AnyDecodedValue`s.
/// - **CDR** (little-endian): `schemaEncoding == "ros2msg"` or `"cdr"` — recursive
///   sequential reader with CDR alignment rules.
///
/// CBOR is deferred to 0.2.0.
public struct DynamicDecoder: Sendable {
    private let registry: any MessageRegistry

    public init(registry: any MessageRegistry) {
        self.registry = registry
    }

    /// Decodes `payload` as `schema` using `encoding`.
    ///
    /// Returns `.null` for any field whose value cannot be extracted from the payload
    /// (e.g. malformed data, missing key in JSON). Never throws on malformed payload —
    /// callers receive a partial result with `.null` fields.
    public func decode(
        schema: MessageSchema,
        payload: Data,
        encoding: String) -> AnyDecodedMessage
    {
        if encoding == "json" {
            return decodeJSON(schema: schema, payload: payload)
        } else {
            // CDR: ros2msg, cdr, cbor-raw — default to CDR
            return decodeCDR(schema: schema, payload: payload)
        }
    }

    // MARK: - JSON decoding

    private func decodeJSON(schema: MessageSchema, payload: Data) -> AnyDecodedMessage {
        guard let obj = try? JSONSerialization.jsonObject(with: payload),
              let dict = obj as? [String: Any] else {
            return AnyDecodedMessage(schemaName: schema.fullName, fields: [:])
        }
        var fields: [String: AnyDecodedValue] = [:]
        for field in schema.fields {
            let raw = dict[field.name]
            fields[field.name] = mapJSONValue(raw, type: field.type)
        }
        return AnyDecodedMessage(schemaName: schema.fullName, fields: fields)
    }

    private func mapJSONValue(_ value: Any?, type fieldType: FieldType) -> AnyDecodedValue {
        guard let value else { return .null }
        switch fieldType {
        case .bool: return (value as? Bool).map { .bool($0) } ?? .null
        case .byte, .uint8: return (value as? Int).map { .uint8(UInt8(clamping: $0)) } ?? .null
        case .char: return (value as? Int).map { .char(UInt8(clamping: $0)) } ?? .null
        case .int8: return (value as? Int).map { .int8(Int8(clamping: $0)) } ?? .null
        case .int16: return (value as? Int).map { .int16(Int16(clamping: $0)) } ?? .null
        case .int32: return (value as? Int).map { .int32(Int32(clamping: $0)) } ?? .null
        case .int64: return (value as? Int).map { .int64(Int64($0)) } ?? .null
        case .uint16: return (value as? Int).map { .uint16(UInt16(clamping: $0)) } ?? .null
        case .uint32: return (value as? Int).map { .uint32(UInt32(clamping: $0)) } ?? .null
        case .uint64: return (value as? Int).map { .uint64(UInt64($0)) } ?? .null
        case .float32: return (value as? Double).map { .float32(Float($0)) } ?? .null
        case .float64: return (value as? Double).map { .float64($0) } ?? .null
        case .string, .wstring: return (value as? String).map { .string($0) } ?? .null
        case .nested(let name):
            if let nestedDict = value as? [String: Any],
               let nestedSchema = registry.schema(for: name) {
                var nested: [String: AnyDecodedValue] = [:]
                for f in nestedSchema.fields { nested[f.name] = mapJSONValue(nestedDict[f.name], type: f.type) }
                return .message(AnyDecodedMessage(schemaName: name, fields: nested))
            }
            return .null
        case .array(let elemType, _), .bounded(let elemType, _):
            if let arr = value as? [Any] {
                return .array(arr.map { mapJSONValue($0, type: elemType) })
            }
            return .null
        }
    }

    // MARK: - CDR little-endian decoding

    private func decodeCDR(schema: MessageSchema, payload: Data) -> AnyDecodedMessage {
        var reader = CDRReader(data: payload)
        // Skip 4-byte encapsulation header if present (0x00 0x01 0x00 0x00 = little-endian).
        // Reset alignmentBase to the data-start offset so CDR field alignment is computed
        // relative to the start of the CDR data, matching ROS2 serialization behavior.
        if payload.count >= 4, payload[0] == 0x00, payload[1] == 0x01 {
            reader.offset = 4
            reader.alignmentBase = 4
        }
        var fields: [String: AnyDecodedValue] = [:]
        for field in schema.fields {
            fields[field.name] = reader.read(type: field.type, registry: registry)
        }
        return AnyDecodedMessage(schemaName: schema.fullName, fields: fields)
    }
}

// MARK: - CDR sequential reader

private struct CDRReader {
    let data: Data
    var offset: Int = 0
    /// Alignment is computed relative to `alignmentBase` (set to the data-start offset
    /// after the encapsulation header so that CDR alignment matches ROS2 serialization).
    var alignmentBase: Int = 0

    mutating func align(to alignment: Int) {
        let logicalOffset = offset - alignmentBase
        let rem = logicalOffset % alignment
        if rem != 0 { offset += alignment - rem }
    }

    mutating func readUInt8() -> UInt8? {
        guard offset < data.count else { return nil }
        defer { offset += 1 }
        return data[offset]
    }

    mutating func readUInt16LE() -> UInt16? {
        align(to: 2)
        guard offset + 2 <= data.count else { return nil }
        defer { offset += 2 }
        return UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    mutating func readUInt32LE() -> UInt32? {
        align(to: 4)
        guard offset + 4 <= data.count else { return nil }
        defer { offset += 4 }
        return UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }

    mutating func readUInt64LE() -> UInt64? {
        align(to: 8)
        guard offset + 8 <= data.count else { return nil }
        defer { offset += 8 }
        var v: UInt64 = 0
        for i in 0..<8 { v |= UInt64(data[offset + i]) << (i * 8) }
        return v
    }

    mutating func readFloat32() -> Float? {
        guard let bits = readUInt32LE() else { return nil }
        return Float(bitPattern: bits)
    }

    mutating func readFloat64() -> Double? {
        guard let bits = readUInt64LE() else { return nil }
        return Double(bitPattern: bits)
    }

    mutating func readCDRString() -> String? {
        guard let length = readUInt32LE(), length > 0 else { return "" }
        let byteCount = Int(length)
        guard offset + byteCount <= data.count else { return nil }
        // CDR strings are null-terminated; drop the null
        let strData = data[offset..<(offset + byteCount - 1)]
        offset += byteCount
        return String(bytes: strData, encoding: .utf8)
    }

    mutating func read(type: FieldType, registry: any MessageRegistry) -> AnyDecodedValue {
        switch type {
        case .bool: return readUInt8().map { .bool($0 != 0) } ?? .null
        case .byte, .uint8: return readUInt8().map { .uint8($0) } ?? .null
        case .char: return readUInt8().map { .char($0) } ?? .null
        case .int8: return readUInt8().map { .int8(Int8(bitPattern: $0)) } ?? .null
        case .uint16: return readUInt16LE().map { .uint16($0) } ?? .null
        case .int16: return readUInt16LE().map { .int16(Int16(bitPattern: $0)) } ?? .null
        case .uint32: return readUInt32LE().map { .uint32($0) } ?? .null
        case .int32: return readUInt32LE().map { .int32(Int32(bitPattern: $0)) } ?? .null
        case .uint64: return readUInt64LE().map { .uint64($0) } ?? .null
        case .int64: return readUInt64LE().map { .int64(Int64(bitPattern: $0)) } ?? .null
        case .float32: return readFloat32().map { .float32($0) } ?? .null
        case .float64: return readFloat64().map { .float64($0) } ?? .null
        case .string, .wstring: return readCDRString().map { .string($0) } ?? .null
        case .nested(let name):
            guard let schema = registry.schema(for: name) else { return .null }
            var fields: [String: AnyDecodedValue] = [:]
            for f in schema.fields { fields[f.name] = read(type: f.type, registry: registry) }
            return .message(AnyDecodedMessage(schemaName: name, fields: fields))
        case .array(let elemType, let count):
            if let count {
                // Fixed-size array
                return .array((0..<count).map { _ in read(type: elemType, registry: registry) })
            } else {
                guard let length = readUInt32LE() else { return .null }
                return .array((0..<Int(length)).map { _ in read(type: elemType, registry: registry) })
            }
        case .bounded(let elemType, _):
            guard let length = readUInt32LE() else { return .null }
            return .array((0..<Int(length)).map { _ in read(type: elemType, registry: registry) })
        }
    }
}
