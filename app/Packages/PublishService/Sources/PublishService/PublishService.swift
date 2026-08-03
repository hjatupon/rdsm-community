import Foundation
import Transport
import Logging

public struct NullLogger: LoggerProtocol, Sendable {
    public init() {}
    public func debug(_ message: String, fields: [LogField]) {}
    public func info(_ message: String, fields: [LogField]) {}
    public func warning(_ message: String, fields: [LogField]) {}
    public func error(_ message: String, fields: [LogField]) {}
}

/// Publishes JSON-encoded ROS2 messages via the existing foxglove_bridge WebSocket.
///
/// **Doctrine carve-out (founder-approved):** Mac stays a network CLIENT — it sends
/// Foxglove `client-advertise` + `client-message-data` frames; the Linux
/// `foxglove_bridge` does the actual ROS2 publish. Mac never runs ROS2 nodes.
///
/// v1 payload format: JSON. Supports primitive helpers (String, Twist) plus a raw
/// JSON escape hatch for any message type. The bridge must advertise the
/// `clientPublish` capability or every call throws `unsupportedOperation`.
public actor PublishService {

    public struct PublishRequest: Sendable {
        public let topic: String
        public let messageType: String
        public let jsonPayload: Data

        public init(topic: String, messageType: String, jsonPayload: Data) {
            self.topic = topic
            self.messageType = messageType
            self.jsonPayload = jsonPayload
        }
    }

    public enum PublishError: Error, LocalizedError {
        case invalidJSON
        case transport(any Error)

        public var errorDescription: String? {
            switch self {
            case .invalidJSON: return "Invalid JSON payload"
            case .transport(let e): return "Transport error: \(e.localizedDescription)"
            }
        }
    }

    private let transport: any TransportClient
    private let logger: any LoggerProtocol
    private var advertisedTopics: Set<String> = []

    public init(transport: any TransportClient, logger: any LoggerProtocol = NullLogger()) {
        self.transport = transport
        self.logger = logger
    }

    /// Publish any message: caller supplies a JSON-encoded payload + the ROS message type.
    public func publish(_ request: PublishRequest) async throws {
        try await ensureAdvertised(topic: request.topic, messageType: request.messageType)
        let msg = TopicMessage(
            topic: request.topic,
            timestamp: 0,
            schemaName: request.messageType,
            payload: request.jsonPayload)
        do {
            try await transport.publish(msg)
        } catch {
            throw PublishError.transport(error)
        }
    }

    /// Convenience: publish a `std_msgs/msg/String` with `{"data": "..."}`.
    public func publishString(topic: String, text: String) async throws {
        let payload: [String: Any] = ["data": text]
        let data = try JSONSerialization.data(withJSONObject: payload)
        try await publish(PublishRequest(topic: topic, messageType: "std_msgs/msg/String", jsonPayload: data))
    }

    /// Convenience: publish a `geometry_msgs/msg/Twist`.
    public func publishTwist(
        topic: String,
        linear: (x: Double, y: Double, z: Double),
        angular: (x: Double, y: Double, z: Double)
    ) async throws {
        let payload: [String: Any] = [
            "linear":  ["x": linear.x,  "y": linear.y,  "z": linear.z],
            "angular": ["x": angular.x, "y": angular.y, "z": angular.z],
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        try await publish(PublishRequest(topic: topic, messageType: "geometry_msgs/msg/Twist", jsonPayload: data))
    }

    /// Convenience: publish a `geometry_msgs/msg/TwistStamped` (required by ros_gz_bridge / nav2 on ROS2 Jazzy).
    public func publishTwistStamped(
        topic: String,
        linear: (x: Double, y: Double, z: Double),
        angular: (x: Double, y: Double, z: Double)
    ) async throws {
        let payload: [String: Any] = [
            "header": ["stamp": ["sec": 0, "nanosec": 0], "frame_id": ""],
            "twist": [
                "linear":  ["x": linear.x,  "y": linear.y,  "z": linear.z],
                "angular": ["x": angular.x, "y": angular.y, "z": angular.z],
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        try await publish(PublishRequest(topic: topic, messageType: "geometry_msgs/msg/TwistStamped", jsonPayload: data))
    }

    public func reset() {
        advertisedTopics.removeAll()
    }

    private func ensureAdvertised(topic: String, messageType: String) async throws {
        if advertisedTopics.contains(topic) { return }
        do {
            try await transport.advertise(topic: topic, schema: messageType)
            advertisedTopics.insert(topic)
        } catch {
            throw PublishError.transport(error)
        }
    }
}
