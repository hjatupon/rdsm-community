# Logging

> M1 · Layer 0 · ROS2 Studio

Structured `os.Logger` wrapper used by every other module. Thread-safe, non-throwing, non-blocking.

## Quick start (< 30 seconds)

```swift
import Logging

let logger = Logger(subsystem: "app.ros2studio", category: "transport")
logger.info("Connected", fields: [
    LogField(key: "url", value: "ws://robot.local:8765"),
    LogField.redacted(key: "token", value: secret),
])
```

View in Console.app — filter by **subsystem: app.ros2studio**.

## Run demo

```bash
swift run --package-path . LoggingDemo
```

## Run tests

```bash
swift test --parallel
```

## API

| Type | Role |
|---|---|
| `LogField` | Key/value metadata; set `redacted: true` to hide the value |
| `LoggerProtocol` | Protocol for mock injection in tests |
| `Logger` | Concrete `os.Logger` wrapper; `Logger.shared` is the app-wide default |

## Integration contract

- `Logger` is `Sendable` — safe to share across threads.
- All methods are non-throwing and non-blocking.
- `os.Logger` is **not** in any public signature.

## Version

`0.1.0` — initial release
