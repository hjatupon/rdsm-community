import Foundation

/// Parses `.msg` text into a ``MessageSchema``.
///
/// Handles the full ROS2 IDL `.msg` grammar subset needed for the builtin catalog:
/// - Primitive types: bool, byte, char, float32, float64, int8/16/32/64, uint8/16/32/64, string, wstring
/// - Nested message types: `pkg/Type` and bare `Type` (same-package)
/// - Fixed arrays: `Type[N]`, unbounded sequences: `Type[]`, bounded: `Type[<=N]`
/// - Constants: `TYPE NAME = value`
/// - Comments: lines starting with `#` or `#` suffix
/// - Blank lines ignored
///
/// Unsupported for 0.1.0: `@verbatim` annotations, multi-line defaults.
public struct MsgParser: Sendable {
    public init() {}

    /// Parse `text` as a `.msg` file belonging to `packageName`.
    ///
    /// - Parameters:
    ///   - text: Raw `.msg` file content.
    ///   - packageName: The ROS2 package that owns this message, e.g. `"geometry_msgs"`.
    ///   - messageName: The message type name, e.g. `"Pose"`.
    /// - Throws: ``MsgParseError`` on malformed input.
    public func parse(
        _ text: String,
        packageName: String,
        messageName: String) throws -> MessageSchema
    {
        var fields: [MessageField] = []
        var constants: [MessageConstant] = []

        for (lineNumber, rawLine) in text.components(separatedBy: "\n").enumerated() {
            let line = stripComment(rawLine).trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            if let constant = try parseConstant(line, lineNumber: lineNumber + 1, packageName: packageName) {
                constants.append(constant)
            } else if let field = try parseField(line, lineNumber: lineNumber + 1, packageName: packageName) {
                fields.append(field)
            } else {
                throw MsgParseError.unrecognizedLine(lineNumber: lineNumber + 1, content: line)
            }
        }

        return MessageSchema(
            packageName: packageName,
            messageName: messageName,
            fields: fields,
            constants: constants)
    }

    // MARK: - Private helpers

    private func stripComment(_ line: String) -> String {
        guard let idx = line.firstIndex(of: "#") else { return line }
        return String(line[..<idx])
    }

    private func parseConstant(_ line: String, lineNumber: Int, packageName: String) throws -> MessageConstant? {
        // Pattern: TYPE NAME=VALUE  or  TYPE NAME = VALUE
        let parts = line.components(separatedBy: "=")
        guard parts.count >= 2 else { return nil }
        let lhsParts = parts[0].trimmingCharacters(in: .whitespaces).components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        guard lhsParts.count == 2 else { return nil }
        let rawType = lhsParts[0]
        let name = lhsParts[1]
        let rawValue = parts.dropFirst().joined(separator: "=").trimmingCharacters(in: .whitespaces)
        // Constants can only be primitive types (no nested or array)
        guard let type = parsePrimitiveType(rawType) else {
            throw MsgParseError.unknownType(rawType, lineNumber: lineNumber)
        }
        return MessageConstant(type: type, name: name, rawValue: rawValue)
    }

    private func parseField(_ line: String, lineNumber: Int, packageName: String) throws -> MessageField? {
        // May have default value after the name: TYPE NAME DEFAULT
        let parts = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        guard parts.count >= 2 else { return nil }
        let rawType = parts[0]
        let name = parts[1]
        let defaultValue: String? = parts.count >= 3 ? parts[2...].joined(separator: " ") : nil

        // Sanity check name
        guard name.first?.isLetter ?? false else { return nil }

        let fieldType = try resolveType(rawType, lineNumber: lineNumber, packageName: packageName)
        return MessageField(name: name, type: fieldType, defaultValue: defaultValue)
    }

    private func resolveType(_ raw: String, lineNumber: Int, packageName: String) throws -> FieldType {
        // Array suffix variants: [], [N], [<=N]
        if raw.hasSuffix("[]") {
            let base = String(raw.dropLast(2))
            let elem = try resolveBaseType(base, lineNumber: lineNumber, packageName: packageName)
            return .array(elem, count: nil)
        }
        if raw.hasSuffix("]"), let bracketStart = raw.lastIndex(of: "[") {
            let content = String(raw[raw.index(after: bracketStart)..<raw.index(before: raw.endIndex)])
            let base = String(raw[..<bracketStart])
            let elem = try resolveBaseType(base, lineNumber: lineNumber, packageName: packageName)
            if content.hasPrefix("<="), let max = Int(content.dropFirst(2)) {
                return .bounded(elem, maxCount: max)
            }
            if let count = Int(content) {
                return .array(elem, count: count)
            }
            throw MsgParseError.malformedArraySuffix(raw, lineNumber: lineNumber)
        }
        return try resolveBaseType(raw, lineNumber: lineNumber, packageName: packageName)
    }

    private func resolveBaseType(_ raw: String, lineNumber: Int, packageName: String) throws -> FieldType {
        if let p = parsePrimitiveType(raw) { return p }
        // Nested type: either "pkg/Type" or "Type" (same package)
        let schemaName: String
        if raw.contains("/") {
            // "geometry_msgs/Quaternion" → "geometry_msgs/msg/Quaternion"
            let slashParts = raw.components(separatedBy: "/")
            if slashParts.count == 2 {
                schemaName = "\(slashParts[0])/msg/\(slashParts[1])"
            } else if slashParts.count == 3 && slashParts[1] == "msg" {
                schemaName = raw  // already canonical
            } else {
                schemaName = raw
            }
        } else {
            schemaName = "\(packageName)/msg/\(raw)"
        }
        return .nested(schemaName: schemaName)
    }

    private func parsePrimitiveType(_ raw: String) -> FieldType? {
        switch raw {
        case "bool": .bool
        case "byte": .byte
        case "char": .char
        case "float32": .float32
        case "float64": .float64
        case "int8": .int8
        case "int16": .int16
        case "int32": .int32
        case "int64": .int64
        case "uint8": .uint8
        case "uint16": .uint16
        case "uint32": .uint32
        case "uint64": .uint64
        case "string": .string
        case "wstring": .wstring
        default: nil
        }
    }
}

/// Errors thrown by ``MsgParser``.
public enum MsgParseError: Error, Sendable, CustomStringConvertible {
    case unknownType(String, lineNumber: Int)
    case malformedArraySuffix(String, lineNumber: Int)
    case unrecognizedLine(lineNumber: Int, content: String)

    public var description: String {
        switch self {
        case .unknownType(let t, let n): "MsgParseError: unknown type '\(t)' at line \(n)"
        case .malformedArraySuffix(let s, let n): "MsgParseError: malformed array suffix '\(s)' at line \(n)"
        case .unrecognizedLine(let n, let c): "MsgParseError: unrecognized line \(n): '\(c)'"
        }
    }
}
