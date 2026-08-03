# Changelog

## 0.1.0 — 2026-05-29

- Initial release: `Codec` protocol + `SerializationError`
- `CBORCodec` via SwiftCBOR 0.6 `CodableCBOREncoder/Decoder` (tag-1 timestamp support built in)
- `JSONCodec` via Foundation `JSONEncoder/JSONDecoder` with optional `prettyPrint`
- `MessagePackCodec` via hirotakan/MessagePacker
- All codecs: `Sendable`, stateless, only `SerializationError` from public API
- Round-trip tests: 10 standard ROS2 message shapes × 3 codecs
- Error mapping tests, Sendable/thread-safety tests
- `SerializationDemo` executable showing all three codecs on a `PoseStamped` payload
- Vendoring note: SwiftCBOR → fork before v1.0 per `08-tech-stack §9`
