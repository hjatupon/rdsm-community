# Serialization

> M2 · Layer 0 · ROS2 Studio · Depends: Logging

Unified CBOR / JSON / MessagePack codec layer. All codecs share one `Codec` protocol;
errors are always `SerializationError` — no raw library errors escape the public API.

## Quick start (< 30 seconds)

```swift
import Serialization

let codec = CBORCodec()                    // or JSONCodec() / MessagePackCodec()
let data  = try codec.encode(myMessage)    // Data
let msg   = try codec.decode(MyMsg.self, from: data)
```

## Run demo

```bash
swift run --package-path . SerializationDemo
```

## Run tests

```bash
swift test --parallel
```

## Codecs

| Codec | Content-Type | Use case |
|---|---|---|
| `CBORCodec` | `application/cbor` | foxglove_bridge protocol (primary) |
| `JSONCodec` | `application/json` | rosbridge v2, settings, layouts |
| `MessagePackCodec` | `application/msgpack` | ROS2 RTPS fallback |

`CBORCodec` uses `CodableCBOREncoder/Decoder` with `dateStrategy: .taggedAsEpochTimestamp`,
which handles foxglove_bridge CBOR **tag 1** timestamps out of the box.

## Integration contract

- All codecs are `Sendable` — share a single instance safely across threads.
- Only `SerializationError` is ever thrown from public API.
- Codecs are stateless — no stored mutable state.

## Version

`0.1.0` — initial release
