import Foundation

/// Persistence abstraction for ``ConnectionProfile`` objects.
///
/// The default ``InMemoryProfileStore`` is used in tests and previews.
/// The real app uses a UserDefaults / plist-backed conformer from the app layer.
public protocol ProfileStoreProtocol: Sendable {
    func load() async -> [ConnectionProfile]
    func save(_ profiles: [ConnectionProfile]) async
}

/// Non-persistent store for tests and previews.
public actor InMemoryProfileStore: ProfileStoreProtocol {
    private var profiles: [ConnectionProfile]

    public init(profiles: [ConnectionProfile] = []) {
        self.profiles = profiles
    }

    public func load() async -> [ConnectionProfile] { profiles }
    public func save(_ profiles: [ConnectionProfile]) async { self.profiles = profiles }
}
