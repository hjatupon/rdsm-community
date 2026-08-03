import Foundation

/// Migrates persisted `LayoutState` JSON forward to the current schema version.
///
/// Strategy: decode as a raw dictionary, apply incremental patches,
/// re-encode, then decode as `LayoutState`. This avoids coupling the migrator
/// to old `Codable` struct versions.
struct LayoutMigrator: Sendable {

    func migrate(data: Data) throws(LayoutEngineError) -> LayoutState {
        guard var dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw .decodingFailed("Could not parse JSON as dictionary")
        }

        let version = dict["version"] as? Int ?? 1

        if version < 2 {
            // v1 → v2: add sidebarWidth with default
            dict["sidebarWidth"] = 260.0
            dict["version"] = 2
        }

        // Future migrations: if version < 3 { … }

        do {
            let patched = try JSONSerialization.data(withJSONObject: dict)
            return try JSONDecoder().decode(LayoutState.self, from: patched)
        } catch {
            throw .migrationFailed(error.localizedDescription)
        }
    }
}
