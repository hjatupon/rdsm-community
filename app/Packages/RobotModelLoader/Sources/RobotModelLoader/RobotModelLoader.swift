import Foundation
import URDFParser
import RobotModelCore
import MeshLoader
import MetalCore
import Logging

/// Module-local NullLogger to avoid the ambiguity between URDFParser.NullLogger
/// and MeshLoader.NullLogger when both are imported.
public struct RobotModelLoaderNullLogger: LoggerProtocol, Sendable {
    public init() {}
    public func debug(_ message: String, fields: [LogField]) {}
    public func info(_ message: String, fields: [LogField]) {}
    public func warning(_ message: String, fields: [LogField]) {}
    public func error(_ message: String, fields: [LogField]) {}
}

/// Layer-3 orchestration: parses URDF → resolves mesh URLs → loads meshes into GPU buffers.
/// v1 supports file://, absolute, and relative paths (resolved against a user-chosen mesh root).
/// `package://foo/...` is best-effort under `<meshRoot>/foo/...`; unresolved meshes are
/// recorded as warnings and skipped (the renderer falls back to placeholder boxes).
public struct RobotModelLoader: Sendable {

    public struct RobotSummaryLink: Sendable {
        public let name: String
        public let hasMesh: Bool
        public let meshKey: String?
    }

    public struct RobotSummaryJoint: Sendable {
        public let name: String
        public let type: String
        public let parent: String
        public let child: String
    }

    public struct RobotModelSummary: Sendable {
        public let rootLink: String
        public let linkCount: Int
        public let jointCount: Int
        public let links: [RobotSummaryLink]
        public let joints: [RobotSummaryJoint]
    }

    public struct LoadedRobot: Sendable {
        public let model: RobotModel
        public let meshes: [String: LoadedMesh]
        public let summary: RobotModelSummary
        public let warnings: [String]
    }

    private let context: MetalContext
    private let parser: URDFParser
    private let logger: any LoggerProtocol

    public init(
        context: MetalContext,
        parser: URDFParser = URDFParser(),
        logger: any LoggerProtocol = RobotModelLoaderNullLogger()
    ) {
        self.context = context
        self.parser = parser
        self.logger = logger
    }

    /// Parse URDF XML and load every available mesh.
    public func loadFromURDF(
        xml: String,
        baseURL: URL? = nil,
        packagePaths: [String: URL] = [:],
        meshRoot: URL? = nil
    ) throws -> LoadedRobot {
        var model = try parser.parse(xml, baseURL: baseURL)
        if !packagePaths.isEmpty {
            model = parser.resolveMeshURLs(model, packagePaths: packagePaths)
        }
        return try resolveAndLoad(model: model, baseURL: baseURL, meshRoot: meshRoot)
    }

    /// Load a URDF file from disk.
    public func loadFromFile(
        _ url: URL,
        packagePaths: [String: URL] = [:],
        meshRoot: URL? = nil
    ) throws -> LoadedRobot {
        let xml = try String(contentsOf: url, encoding: .utf8)
        return try loadFromURDF(
            xml: xml,
            baseURL: url.deletingLastPathComponent(),
            packagePaths: packagePaths,
            meshRoot: meshRoot)
    }

    // MARK: - Internal

    private func resolveAndLoad(model: RobotModel, baseURL: URL?, meshRoot: URL?) throws -> LoadedRobot {
        let loader = MeshLoader(context: context, logger: logger)
        var meshes: [String: LoadedMesh] = [:]
        var warnings: [String] = []

        for link in model.links {
            guard let key = link.meshKey else { continue }
            guard let url = resolveMeshURL(key, baseURL: baseURL, meshRoot: meshRoot) else {
                warnings.append("Could not resolve mesh path for link '\(link.name)': \(key)")
                continue
            }
            do {
                let mesh = try loader.load(from: url)
                meshes[key] = mesh
            } catch {
                warnings.append("Failed to load mesh for link '\(link.name)' from \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }

        let summary = buildSummary(from: model)
        return LoadedRobot(model: model, meshes: meshes, summary: summary, warnings: warnings)
    }

    private func resolveMeshURL(_ key: String, baseURL: URL?, meshRoot: URL?) -> URL? {
        if key.hasPrefix("file://") {
            return URL(string: key)
        }
        if key.hasPrefix("package://") {
            // package://<pkg>/<rest>
            let withoutScheme = key.dropFirst("package://".count)
            let slashIdx = withoutScheme.firstIndex(of: "/")
            let rest = slashIdx.map { String(withoutScheme[$0...].dropFirst()) } ?? String(withoutScheme)

            // 1. meshRoot/<pkg>/<rest> — explicit mapping via Settings
            if let meshRoot {
                let candidate = meshRoot.appendingPathComponent(String(withoutScheme))
                if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            }
            // 2. baseURL/<rest> — strip the package name and look next to the URDF file.
            //    Handles the common case where meshes/ lives beside the URDF (no ROS workspace needed).
            if let baseURL {
                let candidate = baseURL.appendingPathComponent(rest)
                if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            }
            // 3. meshRoot/<rest> — flat meshRoot without package subfolder
            if let meshRoot {
                let candidate = meshRoot.appendingPathComponent(rest)
                if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            }
            return nil
        }
        if key.hasPrefix("/") {
            return URL(fileURLWithPath: key)
        }
        // Relative path
        if let meshRoot {
            return meshRoot.appendingPathComponent(key)
        }
        if let baseURL {
            return baseURL.appendingPathComponent(key)
        }
        return nil
    }

    private func buildSummary(from model: RobotModel) -> RobotModelSummary {
        let links = model.links.map { link in
            RobotSummaryLink(
                name: link.name,
                hasMesh: link.meshKey != nil,
                meshKey: link.meshKey)
        }
        let joints = model.joints.map { joint in
            RobotSummaryJoint(
                name: joint.name,
                type: String(describing: joint.type),
                parent: joint.parent,
                child: joint.child)
        }
        return RobotModelSummary(
            rootLink: model.rootLink,
            linkCount: model.links.count,
            jointCount: model.joints.count,
            links: links,
            joints: joints)
    }
}
