# PublishService — Message Publishing

## Key Types
- `PublishService` (actor) — publish(request:), advertisedTopics dedup set
- `PublishRequest { topic, messageType, jsonPayload }` — topic must start with `/`
- `PublishError { invalidJSON, transport }`

## Convenience Methods
- `publishString(text:)` → std_msgs/String: `{"data": "..."}`
- `publishTwist(linear:, angular:)` → geometry_msgs/Twist
- `publishTwistStamped(linear:, angular:)` → geometry_msgs/TwistStamped: `{"header":{...}, "twist":{...}}`
- `publishJSON(topic:, type:, payload:)` → raw JSON passthrough

## Wire Format
`{"op":"publish","topic":"/cmd_vel","msg":{...}}` (rosbridge publish frame)

## Files
- `PublishService.swift` (123 lines)
- TwistStamped required by ros_gz_bridge for TurtleBot3 Jazzy (not plain Twist)
