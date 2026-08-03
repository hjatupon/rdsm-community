import Foundation
import Logging

/// Live rosbridge.v2 client over URLSession WebSocket.
///
/// ```swift
/// let transport = RosbridgeTransport()
/// try await transport.connect(url: URL(string: "ws://localhost:9090")!, auth: nil)
/// for descriptor in await transport.listTopics() { print(descriptor.name) }
/// let stream = try await transport.subscribe("/scan")
/// for await message in stream { /* … */ }
/// ```
///
/// A `struct` wrapping an internal `actor`, so it stays `Sendable` and can be
/// shared across tasks. See ``TransportClient`` for the concurrency contract.
public struct RosbridgeTransport: TransportClient {
    public let state: AsyncStream<TransportState>
    private let connection: RosbridgeConnectionActor

    public init() {
        self.init(
            connector: URLSessionWebSocketConnector(),
            config: .default,
            logger: Logger(subsystem: "app.ros2studio", category: "transport"))
    }

    public init(config: TransportConfig) {
        self.init(
            connector: URLSessionWebSocketConnector(),
            config: config,
            logger: Logger(subsystem: "app.ros2studio", category: "transport"))
    }

    init(connector: any WebSocketConnecting, config: TransportConfig, logger: any LoggerProtocol) {
        let (stream, continuation) = AsyncStream.makeStream(of: TransportState.self)
        state = stream
        connection = RosbridgeConnectionActor(
            connector: connector, config: config, logger: logger, stateContinuation: continuation)
    }

    public func connect(url: URL) async throws {
        try await connection.connect(url: url)
    }

    public func disconnect() async {
        await connection.disconnect()
    }

    public func listTopics() async throws -> [TopicDescriptor] {
        await connection.listTopics()
    }

    public func subscribe(_ topic: String) async throws -> AsyncStream<TopicMessage> {
        try await connection.subscribe(topic)
    }

    public func unsubscribe(_ topic: String) async throws {
        try await connection.unsubscribe(topic)
    }

    public func advertise(topic: String, schema: String) async throws {
        // rosbridge does not require an explicit advertise step before publishing.
    }

    public func publish(_ message: TopicMessage) async throws {
        try await connection.publish(topic: message.topic, payload: message.payload)
    }

    public func listNodes() async throws -> [String] {
        try await connection.listNodes()
    }

    public func getParameters(node: String) async throws -> [Parameter] {
        try await connection.getParameters(node: node)
    }

    public func setParameter(_ p: Parameter) async throws {
        try await connection.setParameter(p)
    }

    public func serverCapabilities() async -> [String] {
        await connection.capabilities()
    }

    public func currentState() async -> TransportState {
        await connection.lastKnownState
    }

    public func callService(service: String, argsJSON: Data) async throws -> Data {
        try await connection.callService(service: service, argsJSON: argsJSON)
    }
}
