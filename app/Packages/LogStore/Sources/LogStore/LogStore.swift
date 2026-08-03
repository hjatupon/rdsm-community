import Foundation
import TopicStore
import Logging

/// Subscribes to `/rosout` (rcl_interfaces/msg/Log) and keeps a bounded, filterable
/// ring of decoded LogEntry values. Consumed by LogViewerUI.
public actor LogStore {
    private let topicStore: TopicStore
    private let topic: String
    private let capacity: Int
    private let logger: any LoggerProtocol

    private var entries: [LogEntry] = []
    private var subscriptionTask: Task<Void, Never>?

    private struct StreamSubscriber: Sendable {
        let id: UUID
        let continuation: AsyncStream<LogEntry>.Continuation
    }
    private var subscribers: [UUID: AsyncStream<LogEntry>.Continuation] = [:]

    public init(
        topicStore: TopicStore,
        topic: String = "/rosout",
        capacity: Int = 5000,
        logger: any LoggerProtocol = NullLogger()
    ) {
        self.topicStore = topicStore
        self.topic = topic
        self.capacity = capacity
        self.logger = logger
    }

    public func start() {
        guard subscriptionTask == nil else { return }
        let topic = self.topic
        subscriptionTask = Task { [weak self] in
            guard let self else { return }
            do {
                let stream = try await self.topicStore.subscribePayload(topic)
                for await stamped in stream {
                    await self.handlePayload(stamped.value, timestamp: stamped.timestamp)
                }
            } catch {
                // /rosout may not be advertised — fail silently
            }
        }
    }

    public func stop() {
        subscriptionTask?.cancel()
        subscriptionTask = nil
        for continuation in subscribers.values {
            continuation.finish()
        }
        subscribers.removeAll()
    }

    public func snapshot(filter: LogFilter? = nil, limit: Int? = nil) -> [LogEntry] {
        var result: [LogEntry]
        if let filter {
            result = entries.filter { filter.matches($0) }
        } else {
            result = entries
        }
        if let limit, result.count > limit {
            result = Array(result.suffix(limit))
        }
        return result.reversed() // newest first for display
    }

    public func clear() {
        entries.removeAll()
    }

    public func stream() -> AsyncStream<LogEntry> {
        let id = UUID()
        let (stream, continuation) = AsyncStream.makeStream(
            of: LogEntry.self,
            bufferingPolicy: .bufferingNewest(1000))
        subscribers[id] = continuation
        continuation.onTermination = { @Sendable [weak self] _ in
            Task { await self?.removeSubscriber(id) }
        }
        return stream
    }

    private func removeSubscriber(_ id: UUID) {
        subscribers.removeValue(forKey: id)
    }

    private func handlePayload(_ data: Data, timestamp: UInt64) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        guard let level = (json["level"] as? NSNumber)?.uint8Value,
              let severity = LogSeverity(raw: level) else { return }

        let name = (json["name"] as? String) ?? ""
        let msg = (json["msg"] as? String) ?? ""
        let file = (json["file"] as? String) ?? ""
        let function = (json["function"] as? String) ?? ""
        let line = (json["line"] as? NSNumber)?.uint32Value ?? 0

        // Prefer the message's stamp if present; fall back to receive timestamp.
        var ts = timestamp
        if let stamp = json["stamp"] as? [String: Any],
           let sec = (stamp["sec"] as? NSNumber)?.uint64Value,
           let nsec = (stamp["nanosec"] as? NSNumber)?.uint64Value {
            ts = sec * 1_000_000_000 + nsec
        }

        let entry = LogEntry(
            timestampNs: ts,
            severity: severity,
            node: name,
            message: msg,
            file: file,
            function: function,
            line: line)

        entries.append(entry)
        if entries.count > capacity {
            entries.removeFirst(entries.count - capacity)
        }
        for continuation in subscribers.values {
            continuation.yield(entry)
        }
    }
}
