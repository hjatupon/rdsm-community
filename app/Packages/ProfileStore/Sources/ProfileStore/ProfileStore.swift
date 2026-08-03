import Foundation
import Logging

/// Persists connection profiles to a JSON file.
///
/// ## Thread safety
/// `ProfileStore` is a Swift actor — all mutations are serialised.
public actor ProfileStore {

    private let fileURL: URL
    private let logger: any LoggerProtocol

    public init(databaseURL: URL, logger: any LoggerProtocol = NullLogger()) {
        self.fileURL = databaseURL
        self.logger = logger
    }

    // MARK: - Profile CRUD

    /// Inserts or replaces `profile` in the store.
    /// Deduplication: if a profile with the same URL already exists, update it in place
    /// rather than creating a duplicate entry.
    public func save(_ profile: ConnectionProfile) async throws {
        var profiles = try loadFromDisk()
        if let idx = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[idx] = profile
        } else if let urlIdx = profiles.firstIndex(where: { $0.url == profile.url }) {
            // Same URL already exists — update name, keep existing id/record
            profiles[urlIdx].name = profile.name
        } else {
            profiles.append(profile)
        }
        try writeToDisk(profiles)
        logger.debug("ProfileStore: saved \(profile.name) (\(profile.id))", fields: [])
    }

    /// Removes the profile with `id`. Throws if not found.
    public func delete(_ id: UUID) async throws {
        var profiles = try loadFromDisk()
        guard let idx = profiles.firstIndex(where: { $0.id == id }) else {
            throw ProfileStoreError.profileNotFound(id)
        }
        profiles.remove(at: idx)
        try writeToDisk(profiles)
        logger.debug("ProfileStore: deleted \(id)", fields: [])
    }

    /// Returns all saved profiles, sorted by name.
    /// Applies a one-time dedup pass: for profiles sharing the same URL, the entry
    /// with the alphabetically shorter name survives (e.g. "sim-bot" beats "sim bot").
    public func list() async -> [ConnectionProfile] {
        guard let profiles = try? loadFromDisk(), !profiles.isEmpty else { return [] }
        let before = profiles.count
        let deduped = Dictionary(grouping: profiles, by: \.url)
            .values
            .map { group -> ConnectionProfile in
                group.sorted { $0.name.count == $1.name.count
                    ? $0.name < $1.name
                    : $0.name.count < $1.name.count
                }.first!
            }
            .sorted { $0.name < $1.name }
        if deduped.count < before {
            try? writeToDisk(deduped)
        }
        return deduped
    }

    // MARK: - Disk I/O

    private func loadFromDisk() throws -> [ConnectionProfile] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode([ConnectionProfile].self, from: data)
        } catch let e as DecodingError {
            throw ProfileStoreError.decodingFailed(e.localizedDescription)
        } catch {
            throw ProfileStoreError.ioFailed(error.localizedDescription)
        }
    }

    private func writeToDisk(_ profiles: [ConnectionProfile]) throws {
        do {
            let data = try JSONEncoder().encode(profiles)
            try data.write(to: fileURL, options: .atomic)
        } catch let e as EncodingError {
            throw ProfileStoreError.encodingFailed(e.localizedDescription)
        } catch {
            throw ProfileStoreError.ioFailed(error.localizedDescription)
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
