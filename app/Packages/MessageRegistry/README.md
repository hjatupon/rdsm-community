# MessageRegistry (M8)

Catalogs ROS2 message schemas (parsed from `.msg` files), provides O(1) frozen lookup, and dynamically decodes raw payloads into typed `AnyDecodedMessage` values without compile-time schema knowledge.

**Layer:** 2 (Data & Parsing) | **Depends on:** Logging (M1), Serialization (M2)

## Quick Start (≤30 sec)

```swift
import MessageRegistry

// 1. Build the registry
let registry = DefaultMessageRegistry()
BuiltinSchemas().loadAll(into: registry)
registry.freeze()  // O(1) reads after this point

// 2. Look up a schema
let schema = registry.schema(for: "geometry_msgs/msg/Pose")  // or short: "geometry_msgs/Pose"

// 3. Decode a JSON payload
let decoder = DynamicDecoder(registry: registry)
let msg = decoder.decode(schema: schema!, payload: jsonData, encoding: "json")
if case .message(let pos) = msg["position"], case .float64(let x) = pos["x"] {
    print("x = \(x)")
}

// 4. Decode a CDR payload (from foxglove_bridge)
let cdrMsg = decoder.decode(schema: schema!, payload: cdrData, encoding: "ros2msg")
```

## API Surface

| Type | Purpose |
|---|---|
| `FieldType` | All ROS2 IDL primitive + nested + array/bounded types |
| `MessageField` | Field name + type + optional default value |
| `MessageConstant` | Constant name + type + raw value string |
| `MessageSchema` | Parsed .msg: packageName, messageName, fullName, fields, constants |
| `MessageRegistry` (protocol) | Frozen read-only catalog — `schema(for:)`, `allSchemas()` |
| `DefaultMessageRegistry` | NSLock-protected registry with `register(_:)` + `freeze()` |
| `BuiltinSchemas` | Loads 146 vendored ROS2 Jazzy .msg files from 12 packages |
| `AnyDecodedValue` | Recursive enum covering all ROS2 field types |
| `AnyDecodedMessage` | Decoded message: `schemaName` + `[String: AnyDecodedValue]` |
| `DynamicDecoder` | Decodes Data → AnyDecodedMessage for JSON and CDR encodings |
| `MsgParser` | Parses raw .msg text → MessageSchema |

## Contracts

- **C2** — public API frozen; InspectorUI (future) depends on `MessageRegistry` protocol
- **C8** — after `freeze()`: thread-safe, O(1) reads, no further registrations accepted

## Builtin Packages

`std_msgs` · `geometry_msgs` · `sensor_msgs` · `nav_msgs` · `visualization_msgs` · `tf2_msgs` · `rcl_interfaces` · `actionlib_msgs` · `builtin_interfaces` · `shape_msgs` · `trajectory_msgs` · `rosgraph_msgs`

## Known Gaps (0.2.0)

- CBOR dynamic decoding
- Xacro macro expansion (include/property/if already supported)
- Multi-line default values
