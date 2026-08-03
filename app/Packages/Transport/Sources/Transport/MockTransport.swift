import Foundation

/// In-process, deterministic ``TransportClient`` — no network, no Docker.
///
/// Drives downstream modules, demos, and CI. The `.turtlesim` scenario mirrors the
/// `test-env` topics so code written against the mock works unchanged against the
/// live ``FoxgloveTransport``.
public struct MockTransport: TransportClient {
    public let state: AsyncStream<TransportState>
    private let actor: MockActor

    public init(scenario: MockScenario = .turtlesim) {
        self.init(scenario: scenario, emitInterval: .milliseconds(10))
    }

    /// Testing seam: control the synthetic emission cadence.
    init(scenario: MockScenario, emitInterval: Duration) {
        let (stream, continuation) = AsyncStream.makeStream(of: TransportState.self)
        state = stream
        actor = MockActor(
            topics: Self.topics(for: scenario),
            emitInterval: emitInterval,
            stateContinuation: continuation)
    }

    static func topics(for scenario: MockScenario) -> [TopicDescriptor] {
        switch scenario {
        case .turtlesim:
            [
                TopicDescriptor(name: "/rosout", schemaName: "rcl_interfaces/msg/Log", schemaEncoding: "cbor"),
                TopicDescriptor(name: "/turtle1/cmd_vel", schemaName: "geometry_msgs/msg/Twist", schemaEncoding: "cbor"),
                TopicDescriptor(name: "/turtle1/pose", schemaName: "turtlesim/msg/Pose", schemaEncoding: "cbor"),
            ]
        case .empty:
            []
        case let .custom(topics):
            topics
        }
    }

    public func connect(url: URL) async throws {
        await actor.connect()
    }

    public func disconnect() async {
        await actor.disconnect()
    }

    public func listTopics() async throws -> [TopicDescriptor] {
        try await actor.listTopics()
    }

    public func subscribe(_ topic: String) async throws -> AsyncStream<TopicMessage> {
        try await actor.subscribe(topic)
    }

    public func unsubscribe(_ topic: String) async throws {
        await actor.unsubscribe(topic)
    }

    public func advertise(topic: String, schema: String) async throws {
        throw TransportError.unsupportedOperation("advertise")
    }

    public func publish(_ message: TopicMessage) async throws {
        throw TransportError.unsupportedOperation("publish")
    }

    public func getParameters(node: String) async throws -> [Parameter] {
        throw TransportError.unsupportedOperation("getParameters")
    }

    public func setParameter(_ p: Parameter) async throws {
        throw TransportError.unsupportedOperation("setParameter")
    }

    public func currentState() async -> TransportState {
        await actor.connected ? .connected : .disconnected
    }
}

// MARK: - Backing actor

actor MockActor {
    private let topics: [TopicDescriptor]
    private let emitInterval: Duration
    private let stateContinuation: AsyncStream<TransportState>.Continuation
    var connected = false
    private var emitters: [String: Task<Void, Never>] = [:]

    init(topics: [TopicDescriptor], emitInterval: Duration, stateContinuation: AsyncStream<TransportState>.Continuation) {
        self.topics = topics
        self.emitInterval = emitInterval
        self.stateContinuation = stateContinuation
    }

    func connect() {
        stateContinuation.yield(.connecting)
        connected = true
        stateContinuation.yield(.connected)
    }

    func disconnect() {
        connected = false
        for task in emitters.values {
            task.cancel()
        }
        emitters.removeAll()
        stateContinuation.yield(.disconnected)
    }

    func listTopics() throws -> [TopicDescriptor] {
        guard connected else { throw TransportError.notConnected }
        return topics
    }

    func subscribe(_ topic: String) throws -> AsyncStream<TopicMessage> {
        guard connected else { throw TransportError.notConnected }
        guard let descriptor = topics.first(where: { $0.name == topic }) else {
            throw TransportError.protocolViolation("topic not advertised: \(topic)")
        }
        emitters[topic]?.cancel()

        let (stream, continuation) = AsyncStream.makeStream(
            of: TopicMessage.self, bufferingPolicy: .bufferingNewest(256))
        let interval = emitInterval
        emitters[topic] = Task {
            var sequence: UInt64 = 0
            while !Task.isCancelled {
                let payload = Self.syntheticPayload(topic: topic, sequence: sequence)
                let message = TopicMessage(
                    topic: descriptor.name,
                    timestamp: sequence,
                    schemaName: descriptor.schemaName,
                    payload: payload)
                continuation.yield(message)
                sequence += 1
                try? await Task.sleep(for: interval)
            }
            continuation.finish()
        }
        return stream
    }

    func unsubscribe(_ topic: String) {
        emitters.removeValue(forKey: topic)?.cancel()
    }

    /// Deterministic synthetic bytes — monotonically tagged so tests can assert order.
    static func syntheticPayload(topic: String, sequence: UInt64) -> Data {
        var data = Data()
        var seq = sequence.littleEndian
        withUnsafeBytes(of: &seq) { data.append(contentsOf: $0) }
        data.append(contentsOf: Array(topic.utf8.prefix(8)))
        return data
    }
}
