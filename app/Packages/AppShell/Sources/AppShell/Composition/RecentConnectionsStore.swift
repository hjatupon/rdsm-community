import Foundation

/// A single recent connection entry — the last N distinct robots the user connected to.
public struct RecentConnection: Codable, Identifiable, Sendable, Hashable {
    public let id: UUID
    public var name: String
    public var url: URL
    public var lastConnectedAt: Date

    public init(id: UUID = UUID(), name: String, url: URL, lastConnectedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.url = url
        self.lastConnectedAt = lastConnectedAt
    }
}

/// Lightweight store for recent connection history.
///
/// Persists to `UserDefaults` under key `recentConnections`.
/// Thread-safety: call only from `@MainActor` context.
@MainActor
final class RecentConnectionsStore {

    private static let defaultsKey = "recentConnections"
    private static let maxEntries = 3

    private(set) var entries: [RecentConnection] = []

    init() {
        entries = loadFromDefaults()
    }

    /// Record a successful connection. De-dupes by URL, promotes to top, caps at 3.
    func record(name: String, url: URL) {
        // Remove existing entry for this URL if any
        entries.removeAll { $0.url == url }
        // Insert at front (most recent first)
        let entry = RecentConnection(name: name, url: url, lastConnectedAt: Date())
        entries.insert(entry, at: 0)
        // Cap to max
        if entries.count > Self.maxEntries {
            entries = Array(entries.prefix(Self.maxEntries))
        }
        saveToDefaults()
    }

    // MARK: - Persistence

    private func loadFromDefaults() -> [RecentConnection] {
        guard let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
              let decoded = try? JSONDecoder().decode([RecentConnection].self, from: data) else {
            return []
        }
        return decoded
    }

    private func saveToDefaults() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }
}
