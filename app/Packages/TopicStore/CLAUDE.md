# TopicStore — Topic Subscription Hub

## Key Types
- `TopicStore` (actor) — subscribe/subscribePayload/subscribe (typed/raw/untyped), latest/latestRaw, unsubscribe
- `SubscriptionGroup` — one upstream TopicStream fan-out to N downstream AsyncStream continuations
- `RingBuffer<T>` — fixed-capacity circular buffer (default 1024), drop-oldest
- `Timestamped<T> { timestamp: UInt64, value: T }`

## Lifecycle
1. `rawStream(for: topic)` — checks groups[topic]; if absent, creates SubscriptionGroup + RingBuffer + transport subscription
2. `didReceive(msg:)` — pushes to ring buffer, records encoding
3. `removeContinuation(id:)` — cancels upstream when last subscriber drops

## Stream Variants
- `subscribePayload(_:)` → AsyncStream<Timestamped<Data>> (raw bytes)
- `subscribe<T: Decodable>(_:as:)` → AsyncStream<Timestamped<T>> (JSON decoded)
- `subscribe(_:)` → AsyncStream<Timestamped<AnyDecodedMessage>> (DynamicDecoder path)

## Files
- `TopicStore.swift` (227 lines), `SubscriptionGroup.swift` (74 lines), `RingBuffer.swift` (47 lines), `Timestamped.swift` (12 lines)
