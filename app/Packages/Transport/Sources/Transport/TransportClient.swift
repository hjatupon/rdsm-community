import Foundation

/// A client that connects to a ROS2 data source and streams topic messages.
///
/// Two conformers ship:
/// - ``RosbridgeTransport`` — a live `rosbridge.v2` JSON client over `URLSession`.
/// - ``MockTransport`` — deterministic, in-process, no network (for tests, demos, CI).
///
/// ## Concurrency contract (C1)
/// - Per-topic message order is **guaranteed**; cross-topic order is **not**.
/// - ``state`` pauses and resumes across reconnects — it never finishes mid-session.
/// - After the reconnect budget is exhausted, all topic streams finish and
///   operations throw ``TransportError/maxReconnectExceeded``.
///
/// ## v0.1 scope
/// `connect`, `disconnect`, `state`, `listTopics`, `subscribe`, `unsubscribe` are
/// fully implemented. `advertise`, `publish`, `getParameters`, `setParameter`
/// throw ``TransportError/unsupportedOperation(_:)`` — the write path lands in v0.2.
public protocol TransportClient: Sendable {
    /// Connection lifecycle stream. See Contract C1 above.
    var state: AsyncStream<TransportState> { get }

    /// Connects to `url`. Returns once the WebSocket is open.
    func connect(url: URL) async throws

    /// Closes the connection and finishes all active streams.
    func disconnect() async

    /// Lists topics currently advertised by the server.
    func listTopics() async throws -> [TopicDescriptor]

    /// Subscribes to `topic`, returning a bounded (256, drop-oldest) message stream.
    func subscribe(_ topic: String) async throws -> AsyncStream<TopicMessage>

    /// Cancels a subscription and finishes its stream.
    func unsubscribe(_ topic: String) async throws

    /// Advertises a topic for publishing. **v0.1: throws `unsupportedOperation`.**
    func advertise(topic: String, schema: String) async throws

    /// Publishes a message. **v0.1: throws `unsupportedOperation`.**
    func publish(_ message: TopicMessage) async throws

    /// Reads parameters from a node. **v0.1: throws `unsupportedOperation`.**
    func getParameters(node: String) async throws -> [Parameter]

    /// Sets a parameter. **v0.1: throws `unsupportedOperation`.**
    func setParameter(_ p: Parameter) async throws

    /// Lists all running ROS2 node names (e.g. ["/slam_toolbox", "/robot_state_publisher"]).
    /// Default implementation returns `[]` for transports that don't support node discovery.
    func listNodes() async throws -> [String]

    /// Server capabilities reported in `serverInfo` (e.g. ["clientPublish"]).
    /// Default implementation returns `[]` for conformers that don't track this.
    func serverCapabilities() async -> [String]

    /// Returns the instantaneous connection state without waiting for a stream event.
    /// Used by UI components (e.g. ConnectionStatusBadge) that need to seed their
    /// displayed state when they are created after the transport has already connected —
    /// AsyncStream does not replay past events to new subscribers.
    func currentState() async -> TransportState

    /// Calls a ROS 2 service via rosbridge's `call_service` operation.
    /// - Parameters:
    ///   - service: Fully qualified service name (e.g. `/ros2_studio/recorder/start`).
    ///   - argsJSON: Pre-encoded JSON bytes for the arguments dictionary.
    /// - Returns: The raw JSON response bytes from the service response.
    /// - Throws: `TransportError.unsupportedOperation` if the transport doesn't support service calls.
    func callService(service: String, argsJSON: Data) async throws -> Data
}

public extension TransportClient {
    func listNodes() async throws -> [String] { [] }
    func serverCapabilities() async -> [String] { [] }
    func callService(service: String, argsJSON: Data) async throws -> Data {
        throw TransportError.unsupportedOperation("service calls not supported by this transport")
    }
}
