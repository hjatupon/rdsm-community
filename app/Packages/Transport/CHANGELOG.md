# Changelog

## 0.1.0 — 2026-05-29

- Initial release: `TransportClient` protocol + `FoxgloveTransport` + `MockTransport`
- foxglove WebSocket client over `URLSessionWebSocketTask`: handshake, channel↔topic
  mapping, JSON control frames (serverInfo / advertise / unadvertise), binary MessageData
  framing (`[opcode][subId u32-LE][timestamp u64-LE][payload]`)
- Offers both subprotocols `foxglove.sdk.v1` (Rust bridge ≥3.x) and
  `foxglove.websocket.v1` (older C++ bridges); server selects — one client, both bridges.
  Subprotocol negotiated via URLSession's `protocols:` overload so the response validates
- `actor ConnectionActor` state machine with reconnect (backoff 500ms→1s→2s→5s→10s capped,
  10-attempt budget, transparent re-subscribe) — Contract C1
- Per-topic bounded delivery (256, drop-oldest, warn-on-drop); per-topic order guaranteed,
  cross-topic not
- `MockTransport` scenarios (`.turtlesim` / `.empty` / `.custom`) — deterministic, no network
- Public types defined here (not in blueprint): `AuthCredentials`, `Parameter`,
  `ParameterValue`, `TransportError`, `MockScenario`, `TransportConfig`
- v0.1 staged scope: `advertise` / `publish` / `getParameters` / `setParameter` throw
  `unsupportedOperation` (write path lands in v0.2 / Phase-2 M22)
- 23 tests: protocol framing (byte vectors), mock lifecycle/ordering/Sendable, reconnect &
  backoff (scripted fake WebSocket), backpressure drop-oldest
- `TransportDemo` — Milestone A: connect ws://localhost:8765, list topics, subscribe
  /turtle1/pose, print 10 messages, disconnect (`--mock` flag for no-Docker runs).
  **Verified live** against foxglove_bridge 3.2.6 (ros:jazzy) — 5 topics, 10 real Pose frames
- Vendoring note: no third-party deps (URLSession WS). foxglove protocol pinned to v1.
