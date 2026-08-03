# MessageRegistry Changelog

## 0.1.0 — 2026-05-30

Initial release (M8, Week 6).

### Features
- `FieldType` — all ROS2 IDL primitive types + nested message + array/bounded variants
- `MessageField`, `MessageConstant`, `MessageSchema` — parsed .msg representation
- `MessageRegistry` protocol — frozen, thread-safe, O(1) lookup (contract C8)
- `DefaultMessageRegistry` — NSLock-protected build phase + freeze → snapshot
- `MsgParser` — line-oriented .msg parser; handles comments, constants, nested types,
  fixed/unbounded/bounded arrays; xacro-macro and multi-line defaults deferred to 0.2.0
- `BuiltinSchemas` — loads 146 vendored ROS2 Jazzy .msg files from 12 packages
  (std_msgs, geometry_msgs, sensor_msgs, nav_msgs, visualization_msgs, tf2_msgs,
  rcl_interfaces, actionlib_msgs, builtin_interfaces, shape_msgs, trajectory_msgs,
  rosgraph_msgs) at app startup
- `AnyDecodedValue` / `AnyDecodedMessage` — recursive dynamic decoded types
- `DynamicDecoder` — JSON (JSONSerialization) and CDR little-endian sequential decoding;
  returns `.null` on malformed fields rather than throwing

### Contracts validated
- **C2** (used by InspectorUI later — API surface frozen)
- **C8** (frozen + thread-safe + O(1) after `freeze()`)

### Known gaps (0.2.0)
- CBOR dynamic decoding
- Xacro macro expansion
- Multi-line default values
- glTF mesh references in PointCloud2 custom msgs
