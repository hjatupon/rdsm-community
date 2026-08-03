import Foundation
import Transport

/// A live connection to a ROS2 data source.
///
/// Holds the underlying transport and the profile that created it.
/// Handles are value types — equality and hashing are by `id`.
public struct ConnectionHandle: Sendable, Identifiable, Hashable {
    public let id: UUID
    public let profile: ConnectionProfile
    /// The underlying transport. Callers subscribe to topics through it.
    public let transport: any TransportClient

    public static func == (lhs: ConnectionHandle, rhs: ConnectionHandle) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
