# Transport Package — rosbridge v2 Protocol

## Key Types
- `TransportClient` (protocol) — connect/disconnect/subscribe/publish/listTopics/getParameters/setParameter
- `RosbridgeTransport` (struct) — wraps `RosbridgeConnectionActor`
- `RosbridgeConnectionActor` (actor) — ~398 lines, all mutable state actor-isolated
- `TransportConfig` — backoff delays, maxReconnectAttempts (10), topicBufferSize (256), serviceTimeout (15s)

## Wire Format (JSON only, no binary, no handshake)
- Subscribe: `{"op":"subscribe","id":"sub_N","topic":"/foo","type":"..."}`
- Unsubscribe: `{"op":"unsubscribe","id":"sub_N"}`
- Publish: `{"op":"publish","topic":"/foo","msg":{...}}`
- Service call: `{"op":"call_service","id":"...","service":"/rosapi/topics","args":{}}`
- Service response: `{"op":"service_response","id":"...","service":"...","result":true,"values":{...}}`

## Connection Probe (send-based)
`RosbridgeConnectionActor.connectionProbe()` sends `{"op":"set_level","level":"none","id":"probe"}` with 2s timeout via TaskGroup. NOT receive-based — `URLSessionWebSocketTask.receive()` doesn't cancel cooperatively.

## Gotchas
- Port 9090, no subprotocol, no handshake frame
- Reconnect: up to 10 attempts, exponential backoff [0.5,1,2,5,10]s, resubscribes all topics
- Parameters use standard ROS2 services: `/{node}/list_parameters` + `/{node}/get_parameters` + `/{node}/set_parameters`
- Advertise is a no-op (rosbridge doesn't require explicit advertise)
- PointCloud2 wire: base64 data + fields[] (NOT foxglove [[Double]] format)
- OccupancyGrid data: try [Int] first, then base64 decode fallback
