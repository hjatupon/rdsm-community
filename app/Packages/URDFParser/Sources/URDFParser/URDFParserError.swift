import Foundation

/// All errors thrown by ``URDFParser``.
public enum URDFParserError: Error, Sendable, CustomStringConvertible {
    /// The XML is malformed or Foundation's XMLParser rejected it.
    case xmlParseError(String)
    /// The `<robot>` root element is missing.
    case missingRootElement
    /// An attribute required for a given element was absent.
    case missingAttribute(element: String, attribute: String)
    /// A Xacro feature that is not supported in 0.1.0.
    case unsupportedXacroFeature(String)
    /// A referenced Xacro property is not defined.
    case undefinedXacroProperty(String)
    /// A referenced file (xacro:include) could not be read.
    case includeFileNotFound(URL)

    public var description: String {
        switch self {
        case .xmlParseError(let msg): "URDFParserError: XML parse error — \(msg)"
        case .missingRootElement: "URDFParserError: missing <robot> root element"
        case .missingAttribute(let el, let attr): "URDFParserError: <\(el)> missing attribute '\(attr)'"
        case .unsupportedXacroFeature(let f): "URDFParserError: unsupported xacro feature '\(f)'"
        case .undefinedXacroProperty(let p): "URDFParserError: undefined xacro property '\(p)'"
        case .includeFileNotFound(let url): "URDFParserError: include file not found: \(url.path)"
        }
    }
}
