import Foundation

/// A saved connection configuration. Safe to persist to disk.
public struct ConnectionProfile: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public var name: String
    public var url: URL

    public init(id: UUID = UUID(), name: String, url: URL) {
        self.id = id
        self.name = name
        self.url = url
    }
}
