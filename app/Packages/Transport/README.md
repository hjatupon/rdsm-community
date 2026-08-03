# Transport

> M3 · Layer 0 · ROS2 Studio · Depends: Logging, Serialization

foxglove_bridge WebSocket client plus a deterministic in-process mock. Connects
the Mac cockpit to a ROS2 stack **over the network** — the app never touches
hardware (doctrine: Linux is the engine, Mac is the cockpit).

The client offers both WebSocket subprotocols — `foxglove.sdk.v1` (the Rust
foxglove_bridge ≥3.x) and `foxglove.websocket.v1` (older C++ bridges) — and lets
the server pick. The wire protocol (serverInfo / advertise / binary MessageData)
is identical across both, so one client speaks to either bridge.

## Quick start (< 30 seconds)

```swift
import Transport

let transport = FoxgloveTransport()
try await transport.connect(url: URL(string: "ws://localhost:8765")!, auth: nil)

for descriptor in try await transport.listTopics() {
    print(descriptor.name, descriptor.schemaName)
}

let stream = try await transport.subscribe("/turtle1/pose")
for await message in stream {
    print(message.topic, message.timestamp, message.payload.count)
}
await transport.disconnect()
```

No ROS2 handy? Swap in the mock — same API, no network:

```swift
let transport = MockTransport(scenario: .turtlesim)
```

## Run the demo (Milestone A)

```bash
cd test-env && docker compose up -d && cd ..      # start foxglove_bridge
swift run --package-path Packages/Transport TransportDemo
```

Without Docker:

```bash
swift run --package-path Packages/Transport TransportDemo --mock
```

## Run tests

```bash
swift test --package-path Packages/Transport --parallel
```

## Concurrency contract (C1)

- Per-topic message order is **guaranteed**; cross-topic order is **not**.
- `state` pauses across reconnects and **never finishes mid-session**; it finishes
  only after the reconnect budget is exhausted (`.failed`).
- Each subscription is a **bounded buffer (256, drop-oldest)** — a slow consumer
  drops the oldest messages and a warning is logged; the producer never blocks.
- Reconnect backoff: 500ms → 1s → 2s → 5s → 10s (capped). After 10 consecutive
  failures all topic streams finish and operations throw `maxReconnectExceeded`.

## v0.1 scope

Fully implemented: `connect`, `disconnect`, `state`, `listTopics`, `subscribe`,
`unsubscribe`. The write path — `advertise`, `publish`, `getParameters`,
`setParameter` — throws `TransportError.unsupportedOperation` and lands in v0.2
(Phase-2, M22). The protocol surface is complete and locked now.

## Integration contract

- Only `TransportError` is thrown from the public API — no raw URLSession errors escape.
- `FoxgloveTransport` and `MockTransport` are `Sendable` — share one instance across tasks.

## Version

`0.1.0` — initial release
