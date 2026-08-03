import Foundation
import Transport

/// Manages a single upstream topic subscription with fan-out to multiple downstream consumers.
///
/// One `SubscriptionGroup` per topic. The upstream `AsyncStream<TopicMessage>` is
/// consumed by a single background `Task`; each downstream caller gets its own
/// `AsyncStream<Timestamped<TopicMessage>>` continuation driven from the fan-out list.
///
/// All access must be serialised through the owning `TopicStore` actor.
final class SubscriptionGroup: Sendable {
    typealias Continuation = AsyncStream<Timestamped<TopicMessage>>.Continuation

    private let _continuations: LockedBox<[UUID: Continuation]>
    private let _task: LockedBox<Task<Void, Never>?>
    let topic: String

    init(topic: String, upstream: AsyncStream<TopicMessage>, onMessage: @escaping @Sendable (TopicMessage) -> Void) {
        self.topic = topic
        let conts = LockedBox<[UUID: Continuation]>([:])
        let taskBox = LockedBox<Task<Void, Never>?>(nil)
        self._continuations = conts
        self._task = taskBox

        let task = Task {
            for await msg in upstream {
                onMessage(msg)
                let stamped = Timestamped(timestamp: msg.timestamp, value: msg)
                let snapshot = conts.value
                for cont in snapshot.values {
                    // Each continuation has newest-only buffering; yield never blocks siblings.
                    cont.yield(stamped)
                }
            }
            // Upstream finished — close all downstream streams
            let snapshot = conts.value
            for cont in snapshot.values { cont.finish() }
        }
        taskBox.value = task
    }

    func addContinuation(_ continuation: Continuation) -> UUID {
        let id = UUID()
        _continuations.value[id] = continuation
        return id
    }

    func removeContinuation(id: UUID) {
        _continuations.value.removeValue(forKey: id)
    }

    var subscriberCount: Int { _continuations.value.count }

    func cancel() {
        _task.value?.cancel()
        let snapshot = _continuations.value
        for cont in snapshot.values { cont.finish() }
        _continuations.value = [:]
    }
}

// MARK: - LockedBox

/// A thread-safe reference box for mutable state inside `Sendable` types.
final class LockedBox<T>: @unchecked Sendable {
    private var _value: T
    private let lock = NSLock()

    init(_ value: T) { self._value = value }

    var value: T {
        get { lock.withLock { _value } }
        set { lock.withLock { _value = newValue } }
    }
}
