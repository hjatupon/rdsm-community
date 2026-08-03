/// A value paired with a ROS-time capture timestamp (nanoseconds since Unix epoch).
public struct Timestamped<T: Sendable>: Sendable {
    /// Nanoseconds since the Unix epoch, matching `TopicMessage.timestamp`.
    public let timestamp: UInt64
    /// The decoded or raw value.
    public let value: T

    public init(timestamp: UInt64, value: T) {
        self.timestamp = timestamp
        self.value = value
    }
}
