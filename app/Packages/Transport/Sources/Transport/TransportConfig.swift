import Foundation

/// Tuning knobs for ``RosbridgeTransport``. The defaults match Contract C1.
public struct TransportConfig: Sendable {
    /// Reconnect backoff schedule. The last value is reused once exhausted (capped).
    public var backoff: [Duration]
    /// Consecutive reconnect failures tolerated before giving up.
    public var maxReconnectAttempts: Int
    /// Per-topic bounded-buffer size; oldest messages are dropped past this (drop-oldest).
    public var topicBufferSize: Int
    /// Maximum time to wait for a single /rosapi service call response.
    public var serviceTimeout: Duration
    /// Minimum milliseconds between successive publishes of a topic from the bridge (0 = no throttle).
    /// Sent as `throttle_rate` in the rosbridge v2 subscribe op.
    public var subscribeThrottleMs: Int

    public init(
        backoff: [Duration] = [.milliseconds(500), .seconds(1), .seconds(2), .seconds(5), .seconds(10)],
        maxReconnectAttempts: Int = 10,
        topicBufferSize: Int = 256,
        serviceTimeout: Duration = .seconds(15),
        subscribeThrottleMs: Int = 0)
    {
        self.backoff = backoff
        self.maxReconnectAttempts = maxReconnectAttempts
        self.topicBufferSize = topicBufferSize
        self.serviceTimeout = serviceTimeout
        self.subscribeThrottleMs = subscribeThrottleMs
    }

    public static let `default` = TransportConfig()

    /// Returns the backoff delay for a 1-based reconnect attempt, capped at the last entry.
    func backoffDelay(forAttempt attempt: Int) -> Duration {
        guard !backoff.isEmpty else { return .zero }
        let index = min(max(attempt - 1, 0), backoff.count - 1)
        return backoff[index]
    }
}
