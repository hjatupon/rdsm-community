import Logging

// This demo exercises all four log levels with structured fields including a
// redacted one. Run it, then open Console.app → filter by subsystem "app.ros2studio"
// to see the output.

let logger = Logger(subsystem: "app.ros2studio", category: "demo")

logger.debug("Starting LoggingDemo", fields: [
    LogField(key: "module", value: "Logging"),
    LogField(key: "version", value: "0.1.0"),
])

logger.info("Connection established", fields: [
    LogField(key: "url", value: "ws://localhost:8765"),
    LogField(key: "protocol", value: "foxglove_bridge"),
])

logger.warning("Topic backpressure detected", fields: [
    LogField(key: "topic", value: "/camera/image_raw"),
    LogField(key: "dropped", value: "12"),
])

logger.error("Authentication failed", fields: [
    LogField(key: "host", value: "robot-arm-01.local"),
    LogField.redacted(key: "token", value: "supersecret-abc"),
])

// Console tip — also print to stdout so it's visible without Console.app
import Foundation
fputs("""
\n✅  LoggingDemo complete.
   Open Console.app → search for subsystem: app.ros2studio
   You should see 4 log lines: debug / info / warning / error.
   The 'token' field value will appear as <redacted>.\n\n
""", stdout)
