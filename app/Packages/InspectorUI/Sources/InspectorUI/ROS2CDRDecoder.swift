import Foundation

// MARK: - Public API

/// Decodes ROS2 CDR binary messages using their ros2msg schema definition.
/// Used by InspectorViewModel to display live foxglove_bridge data.
enum ROS2CDRDecoder {

    /// Decode `data` (CDR binary) using the ros2msg `schema` definition string.
    /// Returns a JSON-compatible `[String: Any]` on success, nil if schema is empty or
    /// decoding fails.
    static func decode(data: Data, schema: String) -> [String: Any]? {
        let schemas = parseSchemas(schema)
        guard let main = schemas.first, !main.fields.isEmpty else { return nil }
        var reader = CDRReader(data)
        guard reader != nil else { return nil }
        return decodeMessage(&reader!, fields: main.fields, allSchemas: schemas)
    }
}

// MARK: - Schema parsing

private struct SchemaField {
    let name: String
    var typeName: String
    let isDynArray: Bool
    let fixedCount: Int?   // nil = dynamic, n = fixed-size array, 0 = scalar
}

private struct ParsedSchema {
    let name: String  // "" for the root schema
    let fields: [SchemaField]
}

private func parseSchemas(_ definition: String) -> [ParsedSchema] {
    let sep = "================================================================================"
    let parts = definition.components(separatedBy: sep)
    var result: [ParsedSchema] = []
    for (idx, part) in parts.enumerated() {
        var lines = part.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        var schemaName = ""
        if idx > 0 {
            // Sub-schema block: first meaningful line is "MSG: pkg/Type"
            if let msgIdx = lines.firstIndex(where: { $0.hasPrefix("MSG:") }) {
                schemaName = String(lines[msgIdx].dropFirst(4)).trimmingCharacters(in: .whitespaces)
                lines = Array(lines[(msgIdx + 1)...])
            }
        }
        var fields: [SchemaField] = []
        for line in lines {
            let trimmed = line
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            // Skip constant definitions (contain "=")
            if trimmed.contains("=") { continue }
            // "type name" or "type[] name" or "type[N] name"
            let tokens = trimmed.split(separator: " ", maxSplits: 1).map(String.init)
            guard tokens.count == 2 else { continue }
            var rawType = tokens[0]
            let fieldName = tokens[1].trimmingCharacters(in: .whitespaces)
            guard !fieldName.isEmpty else { continue }

            var isDyn = false
            var fixedN: Int? = 0  // 0 = scalar (not array)
            if rawType.hasSuffix("[]") {
                rawType = String(rawType.dropLast(2))
                isDyn = true; fixedN = nil
            } else if let lBracket = rawType.firstIndex(of: "["),
                      let rBracket = rawType.firstIndex(of: "]") {
                let sz = String(rawType[rawType.index(after: lBracket)..<rBracket])
                fixedN = Int(sz) ?? 1
                rawType = String(rawType[..<lBracket])
            }
            fields.append(SchemaField(name: fieldName, typeName: rawType,
                                      isDynArray: isDyn, fixedCount: fixedN))
        }
        result.append(ParsedSchema(name: schemaName, fields: fields))
    }
    return result
}

// MARK: - CDR reader

private struct CDRReader {
    private let bytes: [UInt8]
    private var pos: Int
    private let le: Bool   // true = little-endian

    init?(_ data: Data) {
        let b = [UInt8](data)
        guard b.count >= 4 else { return nil }
        // CDR encapsulation header: byte[0] unused, byte[1] = 0x01 for LE
        bytes = b
        le = (b[1] & 0x01) == 0x01
        pos = 4
    }

    private mutating func align(_ n: Int) {
        guard n > 1 else { return }
        let rem = pos % n; if rem != 0 { pos += n - rem }
    }

    mutating func readBool() -> Bool? {
        guard pos < bytes.count else { return nil }
        defer { pos += 1 }
        return bytes[pos] != 0
    }

    mutating func readU8() -> UInt8? {
        guard pos < bytes.count else { return nil }
        defer { pos += 1 }
        return bytes[pos]
    }

    mutating func readI8() -> Int8? { readU8().map { Int8(bitPattern: $0) } }

    mutating func readU16() -> UInt16? {
        align(2); guard pos + 2 <= bytes.count else { return nil }
        defer { pos += 2 }
        return le ? UInt16(bytes[pos]) | UInt16(bytes[pos+1]) << 8
                  : UInt16(bytes[pos]) << 8 | UInt16(bytes[pos+1])
    }
    mutating func readI16() -> Int16? { readU16().map { Int16(bitPattern: $0) } }

    mutating func readU32() -> UInt32? {
        align(4); guard pos + 4 <= bytes.count else { return nil }
        defer { pos += 4 }
        if le { return UInt32(bytes[pos]) | UInt32(bytes[pos+1])<<8 | UInt32(bytes[pos+2])<<16 | UInt32(bytes[pos+3])<<24 }
        else  { return UInt32(bytes[pos])<<24 | UInt32(bytes[pos+1])<<16 | UInt32(bytes[pos+2])<<8 | UInt32(bytes[pos+3]) }
    }
    mutating func readI32() -> Int32? { readU32().map { Int32(bitPattern: $0) } }

    mutating func readU64() -> UInt64? {
        align(8); guard pos + 8 <= bytes.count else { return nil }
        defer { pos += 8 }
        var v: UInt64 = 0
        if le { for i in 0..<8 { v |= UInt64(bytes[pos+i]) << (8*i) } }
        else  { for i in 0..<8 { v = v << 8 | UInt64(bytes[pos+i]) } }
        return v
    }
    mutating func readI64() -> Int64? { readU64().map { Int64(bitPattern: $0) } }

    mutating func readF32() -> Float? { readU32().map { Float(bitPattern: $0) } }
    mutating func readF64() -> Double? { readU64().map { Double(bitPattern: $0) } }

    mutating func readString() -> String? {
        guard let len = readU32(), len > 0 else { return "" }
        let n = Int(len)
        guard pos + n <= bytes.count else { return nil }
        // String is len bytes including the null terminator
        let s = String(bytes: bytes[pos ..< pos + n - 1], encoding: .utf8) ?? "<utf8-err>"
        pos += n
        return s
    }

    // Reads `count` elements of a scalar type via a closure.
    mutating func readArray<T>(_ count: Int, read: (inout CDRReader) -> T?) -> [T]? {
        var result: [T] = []
        result.reserveCapacity(count)
        for _ in 0 ..< count {
            guard let v = read(&self) else { return result }
            result.append(v)
        }
        return result
    }
}

// MARK: - Message decoder

private func decodeMessage(_ reader: inout CDRReader,
                            fields: [SchemaField],
                            allSchemas: [ParsedSchema]) -> [String: Any] {
    var dict: [String: Any] = [:]
    for field in fields {
        let count: Int
        if let fc = field.fixedCount {
            if fc == 0 { count = 1 }      // scalar
            else { count = fc }           // fixed array
        } else {
            // Dynamic array: read count from wire
            guard let n = reader.readU32() else { break }
            count = Int(n)
        }

        let isArray = field.isDynArray || (field.fixedCount != nil && field.fixedCount! > 0)

        if isArray {
            dict[field.name] = decodeArray(&reader, type: field.typeName, count: count, allSchemas: allSchemas)
        } else {
            dict[field.name] = decodeScalar(&reader, type: field.typeName, allSchemas: allSchemas) ?? NSNull()
        }
    }
    return dict
}

private func decodeScalar(_ reader: inout CDRReader, type t: String, allSchemas: [ParsedSchema]) -> Any? {
    switch t {
    case "bool":         return reader.readBool()
    case "byte", "uint8", "octet": return reader.readU8().map { Int($0) }
    case "char", "int8": return reader.readI8().map { Int($0) }
    case "uint16":       return reader.readU16().map { Int($0) }
    case "int16":        return reader.readI16().map { Int($0) }
    case "uint32":       return reader.readU32().map { Int($0) }
    case "int32":        return reader.readI32().map { Int($0) }
    case "uint64":       return reader.readU64().map { Int($0) }
    case "int64":        return reader.readI64().map { Int($0) }
    case "float32":      return reader.readF32().map { Double($0) }
    case "float64":      return reader.readF64()
    case "string":       return reader.readString()
    default:
        // Sub-message: look up by last path component or full name
        let short = t.components(separatedBy: "/").last ?? t
        if let sub = allSchemas.first(where: { $0.name.hasSuffix(short) || $0.name == t }),
           !sub.fields.isEmpty {
            return decodeMessage(&reader, fields: sub.fields, allSchemas: allSchemas)
        }
        return nil
    }
}

private func decodeArray(_ reader: inout CDRReader, type t: String, count: Int,
                          allSchemas: [ParsedSchema]) -> Any {
    // Cap array display at 32 elements to keep Inspector readable
    let displayCount = min(count, 32)
    switch t {
    case "float32":
        var vals: [Double] = []
        for _ in 0 ..< count {
            if let v = reader.readF32() { if vals.count < displayCount { vals.append(Double(v)) } }
            else { break }
        }
        return vals.count == count ? vals : vals + ["…+\(count - displayCount) more"]
    case "float64":
        var vals: [Double] = []
        for _ in 0 ..< count {
            if let v = reader.readF64() { if vals.count < displayCount { vals.append(v) } }
            else { break }
        }
        return vals
    case "uint8", "byte", "octet":
        var vals: [Int] = []
        for _ in 0 ..< count {
            if let v = reader.readU8() { if vals.count < displayCount { vals.append(Int(v)) } }
            else { break }
        }
        return vals
    case "int32":
        var vals: [Int] = []
        for _ in 0 ..< count {
            if let v = reader.readI32() { if vals.count < displayCount { vals.append(Int(v)) } }
            else { break }
        }
        return vals
    case "uint32":
        var vals: [Int] = []
        for _ in 0 ..< count {
            if let v = reader.readU32() { if vals.count < displayCount { vals.append(Int(v)) } }
            else { break }
        }
        return vals
    default:
        var vals: [Any] = []
        for _ in 0 ..< count {
            if let v = decodeScalar(&reader, type: t, allSchemas: allSchemas) {
                if vals.count < displayCount { vals.append(v) }
            } else { break }
        }
        return vals
    }
}
