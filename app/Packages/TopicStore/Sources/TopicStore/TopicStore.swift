import Foundation
import Transport
import MessageRegistry
import Logging

// MARK: - TopicStore

/// Central data hub for ROS2 Studio.
///
/// Multiplexes `TransportClient` subscriptions (or `MCAPReader` streams — Contract C5)
/// into per-topic ring-buffered caches and typed `AsyncStream`s for UI consumption.
///
/// ## Threading model (Contract C3)
/// `TopicStore` is a Swift actor. All callbacks arrive on the actor's executor —
/// callers must **not** assume MainActor delivery.
///
/// ## Usage
/// ```swift
/// let store = TopicStore(transport: myTransport, registry: registry)
///
/// // Typed subscription (JSON-encoded topics):
/// let stream = try await store.subscribe("/turtle1/pose", as: TurtlePose.self)
/// for await msg in stream { print(msg.value) }
///
/// // Untyped subscription (any encoding):
/// let rawStream = try await store.subscribe("/turtle1/cmd_vel")
/// for await msg in rawStream { print(msg.value.fields) }
/// ```
public actor TopicStore {

    // MARK: - State

    /// The underlying transport — accessible without `await` since it's set in init and never mutated.
    public nonisolated let transport: any TransportClient
    private let registry: any MessageRegistry
    private let logger: any LoggerProtocol
    private let cacheCapacity: Int

    /// One group per active topic.
    private var groups: [String: SubscriptionGroup] = [:]
    /// Ring buffer of raw `TopicMessage` per topic.
    private var ringBuffers: [String: RingBuffer<TopicMessage>] = [:]
    /// Schema encoding per topic (learned on first message).
    private var topicEncodings: [String: String] = [:]

    // MARK: - Init

    public init(
        transport: any TransportClient,
        registry: any MessageRegistry,
        cacheCapacity: Int = 1024,
        logger: any LoggerProtocol = NullLogger()
    ) {
        self.transport = transport
        self.registry = registry
        self.cacheCapacity = cacheCapacity
        self.logger = logger
    }

    // MARK: - Public API

    /// Returns all topics currently advertised by the connected transport.
    public func availableTopics() async throws -> [TopicDescriptor] {
        try await transport.listTopics()
    }

    /// Subscribes to `topic`, decoding each payload as `T` via `JSONDecoder`.
    ///
    /// Messages whose payload cannot be decoded to `T` are silently dropped.
    /// Returns immediately; the stream is finite only if the transport closes.
    public func subscribe<T: Decodable & Sendable>(
        _ topic: String,
        as type: T.Type
    ) async throws -> AsyncStream<Timestamped<T>> {
        let rawStream = try await rawStream(for: topic)
        let decoder = JSONDecoder()
        return AsyncStream<Timestamped<T>> { continuation in
            Task {
                for await stamped in rawStream {
                    guard let value = try? decoder.decode(T.self, from: stamped.value.payload) else {
                        continue
                    }
                    continuation.yield(Timestamped(timestamp: stamped.timestamp, value: value))
                }
                continuation.finish()
            }
        }
    }

    /// Subscribes to `topic`, returning the raw `Data` payload for each message.
    ///
    /// Use this when the caller needs to parse the bytes itself (e.g. custom binary
    /// or JSON formats that don't map to a fixed Swift type).
    public func subscribePayload(
        _ topic: String
    ) async throws -> AsyncStream<Timestamped<Data>> {
        let raw = try await rawStream(for: topic)
        return AsyncStream<Timestamped<Data>> { continuation in
            Task {
                for await stamped in raw {
                    continuation.yield(Timestamped(timestamp: stamped.timestamp, value: stamped.value.payload))
                }
                continuation.finish()
            }
        }
    }

    /// Subscribes to `topic`, returning the raw transport `TopicMessage`.
    ///
    /// This is the correct hook for consumers that need message metadata without
    /// taking over the underlying transport subscription. Returns the same
    /// fan-out stream used by other subscribers — do not add a second bridge layer.
    public func subscribeRaw(
        _ topic: String
    ) async throws -> AsyncStream<Timestamped<TopicMessage>> {
        try await rawStream(for: topic)
    }

    /// Subscribes to `topic`, returning raw `AnyDecodedMessage` values.
    ///
    /// Uses the `MessageRegistry` and the topic's wire encoding to decode each payload.
    /// Falls back to an empty message when the schema is unknown.
    public func subscribe(_ topic: String) async throws -> AsyncStream<Timestamped<AnyDecodedMessage>> {
        let rawStream = try await rawStream(for: topic)
        let encoding = topicEncodings[topic] ?? "json"
        let reg = registry
        let decoder = DynamicDecoder(registry: reg)
        return AsyncStream<Timestamped<AnyDecodedMessage>> { continuation in
            Task {
                for await stamped in rawStream {
                    let msg = stamped.value
                    let decoded: AnyDecodedMessage
                    if let schema = reg.schema(for: msg.schemaName) {
                        decoded = decoder.decode(
                            schema: schema,
                            payload: msg.payload,
                            encoding: encoding)
                    } else {
                        decoded = AnyDecodedMessage(schemaName: msg.schemaName, fields: [:])
                    }
                    continuation.yield(Timestamped(timestamp: stamped.timestamp, value: decoded))
                }
                continuation.finish()
            }
        }
    }

    /// Returns the most recent cached message for `topic`, decoded as `T`.
    public func latest<T: Decodable & Sendable>(_ topic: String, as type: T.Type) -> Timestamped<T>? {
        guard let msg = ringBuffers[topic]?.latest else { return nil }
        guard let value = try? JSONDecoder().decode(T.self, from: msg.payload) else { return nil }
        return Timestamped(timestamp: msg.timestamp, value: value)
    }

    /// Returns the most recent cached raw message for `topic`.
    public func latestRaw(_ topic: String) -> Timestamped<TopicMessage>? {
        guard let msg = ringBuffers[topic]?.latest else { return nil }
        return Timestamped(timestamp: msg.timestamp, value: msg)
    }

    /// Cancels all downstream streams for `topic` and tears down the upstream subscription
    /// if this was the last subscriber.
    public func unsubscribe(_ topic: String) async {
        guard let group = groups[topic], group.subscriberCount == 0 else {
            groups[topic]?.cancel()
            groups.removeValue(forKey: topic)
            return
        }
        group.cancel()
        groups.removeValue(forKey: topic)
        logger.debug("TopicStore: unsubscribed \(topic)", fields: [])
    }

    /// Number of topics with active upstream subscriptions.
    public var activeTopicCount: Int { groups.count }

    /// Cumulative count of messages received across all topics since this store was created.
    private var _totalReceived: Int = 0
    public var totalReceived: Int { _totalReceived }

    // MARK: - Private helpers

    private func rawStream(for topic: String) async throws -> AsyncStream<Timestamped<TopicMessage>> {
        // Ensure upstream subscription exists
        if groups[topic] == nil {
            let upstream = try await transport.subscribe(topic)
            if ringBuffers[topic] == nil {
                ringBuffers[topic] = RingBuffer(capacity: cacheCapacity)
            }
            if let desc = (try? await transport.listTopics())?.first(where: { $0.name == topic }) {
                topicEncodings[topic] = desc.schemaEncoding
            }
            let logger = self.logger
            let group = SubscriptionGroup(topic: topic, upstream: upstream) { [weak self] msg in
                Task { await self?.didReceive(msg, on: topic) }
                logger.debug("TopicStore: [\(topic)] t=\(msg.timestamp)", fields: [])
            }
            groups[topic] = group
            logger.info("TopicStore: subscribed \(topic)", fields: [])
        }

        // Newest-only buffering so a slow consumer (e.g. MCAP recorder) cannot block fan-out.
        let (stream, continuation) = AsyncStream.makeStream(
            of: Timestamped<TopicMessage>.self,
            bufferingPolicy: .bufferingNewest(cacheCapacity))
        let id = groups[topic]!.addContinuation(continuation)

        // When the stream is cancelled, remove this subscriber
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeContinuation(id: id, topic: topic) }
        }

        return stream
    }

    private func didReceive(_ msg: TopicMessage, on topic: String) {
        _totalReceived += 1
        ringBuffers[topic]?.push(msg)
        if topicEncodings[topic] == nil {
            topicEncodings[topic] = msg.schemaEncoding
        }
    }

    private func removeContinuation(id: UUID, topic: String) {
        groups[topic]?.removeContinuation(id: id)
        if groups[topic]?.subscriberCount == 0 {
            groups[topic]?.cancel()
            groups.removeValue(forKey: topic)
            logger.debug("TopicStore: last subscriber removed for \(topic), upstream cancelled", fields: [])
        }
    }
}

// MARK: - TopicMessage schemaEncoding bridge

private extension TopicMessage {
    /// The wire encoding of this message, derived from the topic descriptor if available.
    /// Defaults to "json" for backward compatibility with MockTransport.
    var schemaEncoding: String { "json" }
}

// MARK: - NullLogger

public struct NullLogger: LoggerProtocol, Sendable {
    public init() {}
    public func debug(_ message: String, fields: [LogField]) {}
    public func info(_ message: String, fields: [LogField]) {}
    public func warning(_ message: String, fields: [LogField]) {}
    public func error(_ message: String, fields: [LogField]) {}
}
