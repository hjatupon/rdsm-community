# LogStore — /rosout Log Storage

## Key Types
- `LogStore` (actor) — subscribe to /rosout via TopicStore, ring buffer (default 5000), snapshot/stream/clear
- `LogEntry { id, timestampNs, severity, node, message, file, function, line }`
- `LogSeverity: debug(10), info(20), warn(30), error(40), fatal(50)`
- `LogFilter { minSeverity, node, substring }` — matches(_:) for filtering

## Files
- `LogEntry.swift` (84 lines), `LogStore.swift` (129 lines)

## Gotchas
- Timestamp: prefers message-level `stamp.{sec, nanosec}` over receive timestamp
- Multicast via stream(): new AsyncStream per subscriber with .bufferingNewest(1000)
- /rosout JSON manually parsed from rcl_interfaces/msg/Log rosbridge format
