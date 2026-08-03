import Foundation

// MARK: - Messages & topics

/// A single message received on a subscribed topic.
///
/// The ``payload`` is left as raw bytes — schema decoding happens downstream
/// (M9 MessageRegistry). Transport only delivers; it never interprets payloads.
public struct TopicMessage: Sendable {
    /// ROS topic name, e.g. `/turtle1/pose`.
    public let topic: String
    /// Capture timestamp in **nanoseconds** since the Unix epoch.
    public let timestamp: UInt64
    /// Schema name advertised for this topic, e.g. `turtlesim/msg/Pose`.
    public let schemaName: String
    /// Encoded message bytes in the topic's wire encoding (see ``TopicDescriptor/schemaEncoding``).
    public let payload: Data

    public init(topic: String, timestamp: UInt64, schemaName: String, payload: Data) {
        self.topic = topic
        self.timestamp = timestamp
        self.schemaName = schemaName
        self.payload = payload
    }
}

/// Describes a topic advertised by the server.
public struct TopicDescriptor: Sendable, Hashable {
    /// ROS topic name.
    public let name: String
    /// Message schema name, e.g. `geometry_msgs/msg/Twist`.
    public let schemaName: String
    /// Wire encoding of the schema, e.g. `cbor`, `json`, `ros2msg`.
    public let schemaEncoding: String
    /// The schema definition text (ros2msg format for ROS2 topics). Used for CDR decoding.
    public let schema: String?

    public init(name: String, schemaName: String, schemaEncoding: String, schema: String? = nil) {
        self.name = name
        self.schemaName = schemaName
        self.schemaEncoding = schemaEncoding
        self.schema = schema
    }
}

// MARK: - Connection state

/// Lifecycle states emitted by ``TransportClient/state``.
///
/// On a dropped connection the stream emits ``reconnecting(attempt:)`` and then
/// resumes — it never finishes mid-session (Contract C1). It finishes only after
/// ``failed(_:)`` when the reconnect budget is exhausted.
public enum TransportState: Sendable {
    case disconnected
    case connecting
    case connected
    case reconnecting(attempt: Int)
    case failed(Error)
}

/// A ROS2 node parameter. Read/write are deferred to v0.2 (Phase-2 write path, M22).
public struct Parameter: Sendable, Hashable {
    public let name: String
    public let value: ParameterValue

    public init(name: String, value: ParameterValue) {
        self.name = name
        self.value = value
    }
}

/// Typed value of a ``Parameter``, mirroring ROS2 parameter types.
public enum ParameterValue: Sendable, Hashable {
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    case boolArray([Bool])
    case intArray([Int64])
    case doubleArray([Double])
    case stringArray([String])
}

// MARK: - Errors

/// All errors surfaced by the public Transport API. No raw URLSession/Foundation
/// error ever escapes.
public enum TransportError: Error, Sendable, Equatable {
    /// An operation requiring a live connection was called while disconnected.
    case notConnected
    /// The foxglove handshake failed (bad subprotocol, malformed serverInfo, …).
    case handshakeFailed(reason: String)
    /// A write-path operation not implemented in v0.1 (advertise/publish/parameters).
    case unsupportedOperation(String)
    /// The reconnect budget (default 10 consecutive failures) was exhausted.
    case maxReconnectExceeded
    /// The server sent a frame that violates the foxglove.websocket.v1 protocol.
    case protocolViolation(String)
    /// A service call received no response within the allowed timeout.
    case timeout
    /// rosbridge returned result:false or set_parameters returned successful:false.
    case serviceCallFailed(reason: String)
}

extension TransportError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to a robot."
        case .handshakeFailed(let reason):
            return "Could not connect — \(reason)"
        case .unsupportedOperation(let op):
            return "Operation not supported: \(op)"
        case .maxReconnectExceeded:
            return "Connection lost — reconnect limit reached."
        case .protocolViolation(let detail):
            return "Protocol error — \(detail)"
        case .timeout:
            return "Service call timed out."
        case .serviceCallFailed(let reason):
            return "Service call failed: \(reason)"
        }
    }
}

// MARK: - Mock scenarios

/// Deterministic scenarios for ``MockTransport`` — no network required.
public enum MockScenario: Sendable {
    /// Advertises `/turtle1/pose`, `/turtle1/cmd_vel`, `/rosout` and emits synthetic messages.
    case turtlesim
    /// No topics, no messages.
    case empty
    /// A caller-supplied topic list; messages are emitted for each on subscribe.
    case custom([TopicDescriptor])
}
