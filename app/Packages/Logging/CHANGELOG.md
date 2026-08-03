# Changelog

## 0.1.0 — 2026-05-29

- Initial release: `LogField`, `LoggerProtocol`, `Logger` wrapping `os.Logger`
- Redaction support: `LogField.redacted(key:value:)` substitutes `<redacted>` in log output
- `Logger.shared` app-wide default (subsystem `app.ros2studio`, category `general`)
- `LoggingDemo` executable: all 4 levels + redacted field, viewable in Console.app
- Unit tests via swift-testing: level routing, redaction, concurrency, Sendable contract
