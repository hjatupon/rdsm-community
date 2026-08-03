import Foundation
import RobotModelCore
import Logging

/// Parses URDF (Unified Robot Description Format) XML — and a useful subset of
/// Xacro preprocessing — into a ``RobotModel``.
///
/// ## Supported features
/// - Standard URDF elements: `<robot>`, `<link>`, `<joint>`, `<origin>`, `<axis>`,
///   `<geometry>` (box / cylinder / sphere / mesh), `<visual>`, `<collision>`
/// - Joint types: revolute, continuous, prismatic, fixed, floating, planar
/// - Xacro subset: `<xacro:include>`, `<xacro:property>`, `<xacro:if>`, `<xacro:unless>`
///
/// ## Not supported in 0.1.0
/// - `<xacro:macro>` / `<xacro:insert_block>` — throws ``URDFParserError/unsupportedXacroFeature(_:)``
/// - Inertial / dynamics / limits — parsed but not exposed in `RobotModel`
///
/// ## Usage
/// ```swift
/// let parser = URDFParser()
/// let model = try parser.parse(contentsOf: urdfURL)
/// ```
///
/// Contract C7: `URDFParser` produces a `RobotModel` value type. It never imports
/// Metal, references renderers, or talks to network/hardware.
public struct URDFParser: Sendable {
    private let logger: any LoggerProtocol

    public init(logger: any LoggerProtocol = NullLogger()) {
        self.logger = logger
    }

    // MARK: - Public API

    /// Parses URDF/Xacro XML from a `String`.
    ///
    /// - Parameters:
    ///   - xml: The raw XML string (may contain Xacro directives).
    ///   - baseURL: Directory used to resolve relative `<xacro:include>` paths.
    ///              Pass `nil` when the URDF has no includes.
    /// - Returns: A fully-populated `RobotModel`.
    /// - Throws: ``URDFParserError``
    public func parse(_ xml: String, baseURL: URL? = nil) throws -> RobotModel {
        logger.debug("URDFParser: preprocessing xacro", fields: [])
        var preprocessor = XacroPreprocessor(baseURL: baseURL)
        let processed = try preprocessor.preprocess(xml)

        logger.debug("URDFParser: running XMLParser", fields: [])
        guard let data = processed.data(using: .utf8) else {
            throw URDFParserError.xmlParseError("Failed to encode XML as UTF-8")
        }
        return try parseData(data)
    }

    /// Parses a URDF/Xacro file at `url`.
    ///
    /// The file's parent directory is used as `baseURL` for includes.
    public func parse(contentsOf url: URL) throws -> RobotModel {
        let xml: String
        do {
            xml = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw URDFParserError.xmlParseError("Could not read file: \(url.path) — \(error.localizedDescription)")
        }
        return try parse(xml, baseURL: url.deletingLastPathComponent())
    }

    /// Resolves `package://` mesh URIs in the model's links using a package-path map.
    ///
    /// Returns a new `RobotModel` where each link's `meshKey` (if present) has been
    /// replaced with an absolute `file://` URL string. Links whose package is unknown
    /// retain the original `package://` key.
    ///
    /// - Parameters:
    ///   - model: The model produced by ``parse(_:baseURL:)`` or ``parse(contentsOf:)``.
    ///   - packagePaths: Map of ROS package names to their local root directories.
    public func resolveMeshURLs(_ model: RobotModel, packagePaths: [String: URL]) -> RobotModel {
        guard !packagePaths.isEmpty else { return model }
        let resolver = MeshURLResolver(packagePaths: packagePaths)
        let resolvedLinks = model.links.map { link -> Link in
            guard let key = link.meshKey else { return link }
            let resolved = resolver.resolve(key)?.absoluteString ?? key
            return Link(name: link.name, meshKey: resolved, meshScale: link.meshScale, visualOrigin: link.visualOrigin)
        }
        return RobotModel(links: resolvedLinks, joints: model.joints, rootLink: model.rootLink)
    }

    // MARK: - Private

    private func parseData(_ data: Data) throws -> RobotModel {
        let delegate = URDFXMLDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        parser.shouldReportNamespacePrefixes = false

        let success = parser.parse()

        if !success || delegate.parseError != nil {
            throw delegate.parseError ?? URDFParserError.xmlParseError("Unknown XML parse failure")
        }
        return try delegate.buildModel()
    }
}

// MARK: - NullLogger for URDFParser

/// Minimal logger that discards all messages. Used as the default when no logger is injected.
public struct NullLogger: LoggerProtocol, Sendable {
    public init() {}
    public func debug(_ message: String, fields: [LogField]) {}
    public func info(_ message: String, fields: [LogField]) {}
    public func warning(_ message: String, fields: [LogField]) {}
    public func error(_ message: String, fields: [LogField]) {}
}
