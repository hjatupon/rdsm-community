import Foundation

/// A saved connection configuration that can be persisted and restored.
public struct ConnectionProfile: Sendable, Identifiable, Hashable, Codable {
    public let id: UUID
    public var name: String
    public var url: URL

    public init(id: UUID = UUID(), name: String, url: URL) {
        self.id = id
        self.name = name
        self.url = url
    }
}
