import Foundation

/// Preprocesses a URDF/Xacro XML string, resolving the subset of Xacro features
/// supported in 0.1.0: `<xacro:include>`, `<xacro:property>`, `<xacro:if>`.
///
/// Macros (`<xacro:macro>` / `<xacro:insert_block>`) are NOT supported and will
/// cause ``URDFParserError/unsupportedXacroFeature(_:)`` to be thrown.
///
/// The preprocessor works at the text level before handing the result to
/// Foundation's `XMLParser`, so it must produce well-formed XML.
struct XacroPreprocessor {
    private var properties: [String: String] = [:]
    private let baseURL: URL?
    private var visited: Set<String> = []

    init(baseURL: URL?) {
        self.baseURL = baseURL
    }

    /// Returns the XML string with Xacro directives resolved.
    mutating func preprocess(_ xml: String) throws -> String {
        // Parse the full document to detect macro usage before doing text substitution.
        // We use a lightweight scan for `<xacro:macro` to fail-fast.
        if xml.contains("<xacro:macro") || xml.contains("<xacro:insert_block") {
            throw URDFParserError.unsupportedXacroFeature("xacro:macro / xacro:insert_block")
        }
        return try resolve(xml: xml, currentBaseURL: baseURL)
    }

    // MARK: - Resolution pipeline

    private mutating func resolve(xml: String, currentBaseURL: URL?) throws -> String {
        var result = xml
        result = try resolveIncludes(in: result, currentBaseURL: currentBaseURL)
        result = try collectProperties(from: result)
        result = substituteProperties(in: result)
        result = try evaluateIf(in: result)
        return result
    }

    // MARK: - xacro:include

    private mutating func resolveIncludes(in xml: String, currentBaseURL: URL?) throws -> String {
        // Match <xacro:include filename="..."/> or <xacro:include filename='...'/>
        let pattern = #"<xacro:include\s+filename=["']([^"']+)["']\s*/>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return xml }
        var result = xml
        // Process includes iteratively (each substitution may shift offsets)
        while let match = regex.firstMatch(
            in: result,
            range: NSRange(result.startIndex..., in: result))
        {
            let fullRange = Range(match.range, in: result)!
            let filenameRange = Range(match.range(at: 1), in: result)!
            let filename = String(result[filenameRange])

            let fileURL = resolveFilename(filename, relativeTo: currentBaseURL)
            let absPath = fileURL.path

            guard !visited.contains(absPath) else {
                // Already included — drop the directive (cycle guard)
                result.replaceSubrange(fullRange, with: "")
                continue
            }
            visited.insert(absPath)

            guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else {
                throw URDFParserError.includeFileNotFound(fileURL)
            }
            // Strip XML declaration from included fragments
            let stripped = stripXMLDeclaration(text)
            // Recursively resolve includes in the included file
            let resolved = try resolveIncludes(
                in: stripped,
                currentBaseURL: fileURL.deletingLastPathComponent())
            result.replaceSubrange(fullRange, with: resolved)
        }
        return result
    }

    private func resolveFilename(_ filename: String, relativeTo base: URL?) -> URL {
        // package:// URIs are not resolved here — caller must use MeshURLResolver
        if filename.hasPrefix("/") {
            return URL(fileURLWithPath: filename)
        }
        if let base {
            return base.appendingPathComponent(filename)
        }
        return URL(fileURLWithPath: filename)
    }

    private func stripXMLDeclaration(_ xml: String) -> String {
        var s = xml.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("<?xml") {
            if let end = s.range(of: "?>") {
                s = String(s[end.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return s
    }

    // MARK: - xacro:property

    /// Scans for `<xacro:property name="..." value="..."/>` elements, stores their
    /// values, and removes the directives from the XML string.
    private mutating func collectProperties(from xml: String) throws -> String {
        let pattern = #"<xacro:property\s+name=["']([^"']+)["']\s+value=["']([^"']*)["']\s*/>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return xml }
        var result = xml
        var offset = result.startIndex

        while let match = regex.firstMatch(
            in: result,
            range: NSRange(offset..., in: result))
        {
            let fullRange = Range(match.range, in: result)!
            let nameRange = Range(match.range(at: 1), in: result)!
            let valueRange = Range(match.range(at: 2), in: result)!
            let name = String(result[nameRange])
            let value = String(result[valueRange])
            properties[name] = value
            result.replaceSubrange(fullRange, with: "")
            // After removal offset stays at the position of the replaced range start
            offset = fullRange.lowerBound
        }
        return result
    }

    // MARK: - Property substitution (${property_name})

    private func substituteProperties(in xml: String) -> String {
        guard !properties.isEmpty else { return xml }
        var result = xml
        // Replace ${name} expressions with their stored values
        for (name, value) in properties {
            result = result.replacingOccurrences(of: "${\(name)}", with: value)
        }
        // Also handle $(arg name) style — treat as passthrough for 0.1.0
        return result
    }

    // MARK: - xacro:if / xacro:unless

    /// Evaluates `<xacro:if value="...">…</xacro:if>` blocks.
    /// Falsy = "0", "false", "False", "FALSE". Anything else is truthy.
    /// `<xacro:unless>` is the complement.
    private mutating func evaluateIf(in xml: String) throws -> String {
        var result = xml
        result = try evaluateConditional(tag: "xacro:if", negate: false, in: result)
        result = try evaluateConditional(tag: "xacro:unless", negate: true, in: result)
        return result
    }

    private mutating func evaluateConditional(
        tag: String,
        negate: Bool,
        in xml: String) throws -> String
    {
        var result = xml
        // Match opening tag with value attribute
        let openPattern = #"<\#(tag)\s+value=["']([^"']*)["']\s*>"#
        let closeTag = "</\(tag)>"
        guard let openRegex = try? NSRegularExpression(pattern: openPattern) else { return xml }

        while let openMatch = openRegex.firstMatch(
            in: result,
            range: NSRange(result.startIndex..., in: result))
        {
            let openRange = Range(openMatch.range, in: result)!
            let valueRange = Range(openMatch.range(at: 1), in: result)!
            var condition = isTruthy(String(result[valueRange]))
            if negate { condition = !condition }

            // Find the matching close tag
            guard let closeRange = result.range(of: closeTag, range: openRange.upperBound..<result.endIndex) else {
                // Malformed — drop the open tag and continue
                result.replaceSubrange(openRange, with: "")
                continue
            }

            let bodyRange = openRange.upperBound..<closeRange.lowerBound
            let body = String(result[bodyRange])

            let fullRange = openRange.lowerBound..<closeRange.upperBound
            if condition {
                result.replaceSubrange(fullRange, with: body)
            } else {
                result.replaceSubrange(fullRange, with: "")
            }
        }
        return result
    }

    private func isTruthy(_ value: String) -> Bool {
        let falsyValues: Set<String> = ["0", "false", "False", "FALSE"]
        return !falsyValues.contains(value)
    }
}
