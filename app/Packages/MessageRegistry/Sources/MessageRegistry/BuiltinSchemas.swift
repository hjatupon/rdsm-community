import Foundation
import Logging

/// Loads all vendored `.msg` files from `Resources/builtins/` and registers them
/// with a ``DefaultMessageRegistry``.
///
/// Call ``loadAll(into:)`` once at app startup (or test setUp) to populate the catalog
/// before freezing the registry.
public struct BuiltinSchemas: Sendable {
    private let parser = MsgParser()

    public init() {}

    /// Registers every bundled `.msg` schema into `registry`.
    ///
    /// Any file that fails to parse is logged as a warning and skipped — the catalog is
    /// partial but never absent.
    public func loadAll(into registry: DefaultMessageRegistry, logger: any LoggerProtocol = NullLogger()) {
        guard let resourceURL = Bundle.module.resourceURL else {
            logger.warning("BuiltinSchemas: Bundle.module.resourceURL is nil — no schemas loaded")
            return
        }
        // With .copy("Resources/builtins") in Package.swift, "builtins" is at the bundle root.
        let builtinsURL = resourceURL.appendingPathComponent("builtins")
        loadDirectory(builtinsURL, registry: registry, logger: logger)
    }

    private func loadDirectory(
        _ dir: URL,
        registry: DefaultMessageRegistry,
        logger: any LoggerProtocol)
    {
        guard let packages = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles) else { return }

        for pkgURL in packages.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: pkgURL.path, isDirectory: &isDir), isDir.boolValue else { continue }
            let packageName = pkgURL.lastPathComponent
            guard let msgFiles = try? FileManager.default.contentsOfDirectory(
                at: pkgURL,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles) else { continue }

            for msgURL in msgFiles.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
            where msgURL.pathExtension == "msg" {
                let messageName = String(msgURL.deletingPathExtension().lastPathComponent)
                do {
                    let text = try String(contentsOf: msgURL, encoding: .utf8)
                    let schema = try parser.parse(text, packageName: packageName, messageName: messageName)
                    registry.register(schema)
                } catch {
                    logger.warning(
                        "BuiltinSchemas: failed to parse \(packageName)/\(messageName).msg",
                        fields: [LogField(key: "error", value: error.localizedDescription)])
                }
            }
        }
    }
}
