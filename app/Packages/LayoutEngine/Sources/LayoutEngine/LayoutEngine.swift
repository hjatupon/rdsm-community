import Foundation
import Logging

/// Saves and loads named workspace layouts as JSON files under `localURL`.
///
/// ## File layout
/// ```
/// <localURL>/
///   layouts/
///     default.json
///     my-robot-lab.json
/// ```
///
/// ## iCloud sync (Phase 2)
/// `changes` is wired to CloudKit change tokens in Phase 2. In v0.1 the stream
/// is present but never emits — call sites can forward-compatibly `for await name in engine.changes`.
public actor LayoutEngine {

    private let layoutsDir: URL
    private let migrator: LayoutMigrator
    private let logger: any LoggerProtocol

    // iCloud stub — Phase 2 will attach a CKDatabaseSubscription here
    public let changes: AsyncStream<String>
    private let changesContinuation: AsyncStream<String>.Continuation

    public init(localURL: URL, cloudContainer: String? = nil, logger: any LoggerProtocol = NullLogger()) {
        self.layoutsDir = localURL.appendingPathComponent("layouts", isDirectory: true)
        self.migrator = LayoutMigrator()
        self.logger = logger

        var cont: AsyncStream<String>.Continuation!
        self.changes = AsyncStream { cont = $0 }
        self.changesContinuation = cont
    }

    // MARK: - CRUD

    /// Serialises `state` and writes it to `<localURL>/layouts/<name>.json`.
    public func save(_ state: LayoutState, named name: String) async throws {
        try ensureLayoutsDir()
        let url = fileURL(for: name)
        do {
            let data = try JSONEncoder().encode(state)
            try data.write(to: url, options: .atomic)
            logger.debug("LayoutEngine: saved '\(name)'", fields: [])
        } catch let e as EncodingError {
            throw LayoutEngineError.encodingFailed(e.localizedDescription)
        } catch {
            throw LayoutEngineError.ioFailed(error.localizedDescription)
        }
    }

    /// Loads and migrates the named layout. Returns the current-version `LayoutState`.
    public func load(named name: String) async throws -> LayoutState {
        let url = fileURL(for: name)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw LayoutEngineError.layoutNotFound(name)
        }
        do {
            let data = try Data(contentsOf: url)
            // Fast path: already current version
            if let state = try? JSONDecoder().decode(LayoutState.self, from: data),
               state.version == LayoutState.currentVersion {
                return state
            }
            // Migration path
            return try migrator.migrate(data: data)
        } catch let e as LayoutEngineError {
            throw e
        } catch {
            throw LayoutEngineError.ioFailed(error.localizedDescription)
        }
    }

    /// Returns the names of all saved layouts, sorted alphabetically.
    public func list() async -> [String] {
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: layoutsDir.path) else {
            return []
        }
        return items
            .filter { $0.hasSuffix(".json") }
            .map { String($0.dropLast(".json".count)) }
            .sorted()
    }

    /// Deletes the named layout file. Throws if not found.
    public func delete(named name: String) async throws {
        let url = fileURL(for: name)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw LayoutEngineError.layoutNotFound(name)
        }
        do {
            try FileManager.default.removeItem(at: url)
            logger.debug("LayoutEngine: deleted '\(name)'", fields: [])
        } catch {
            throw LayoutEngineError.ioFailed(error.localizedDescription)
        }
    }

    // MARK: - Private

    private func fileURL(for name: String) -> URL {
        layoutsDir.appendingPathComponent("\(name).json")
    }

    private func ensureLayoutsDir() throws {
        do {
            try FileManager.default.createDirectory(at: layoutsDir, withIntermediateDirectories: true)
        } catch {
            throw LayoutEngineError.ioFailed("Cannot create layouts directory: \(error.localizedDescription)")
        }
    }
}

// MARK: - NullLogger

public struct NullLogger: LoggerProtocol, Sendable {
    public init() {}
    public func debug(_ message: String, fields: [LogField]) {}
    public func info(_ message: String, fields: [LogField]) {}
    public func warning(_ message: String, fields: [LogField]) {}
    public func error(_ message: String, fields: [LogField]) {}
}
