/// Read-only view of a frozen message schema catalog.
///
/// Conformers must be `Sendable` and support concurrent reads. ``DefaultMessageRegistry``
/// is the standard implementation; it is built with ``MessageRegistryBuilder`` and then
/// frozen before being passed to consumers.
///
/// ## Integration contract C8
/// - After the registry is passed to a consumer it **must** be frozen (no further writes).
/// - All reads are O(1) — dict lookup with no allocation.
/// - All reads are thread-safe — concurrent `schema(for:)` calls on multiple threads
///   require no external synchronization.
public protocol MessageRegistry: Sendable {
    /// Returns the schema for `name`, or `nil` if unknown.
    ///
    /// Accepts both the full form (`"geometry_msgs/msg/Pose"`) and the short form
    /// (`"geometry_msgs/Pose"`). Implementations must resolve both.
    func schema(for name: String) -> MessageSchema?

    /// All schemas in the registry. Order is unspecified.
    func allSchemas() -> [MessageSchema]
}
