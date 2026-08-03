import Foundation
import Transport

// Connect to a live ROS2 stack via rosbridge_suite.
//
//   cd app/testing/sim-bot && docker compose up -d   # start rosbridge
//   swift run --package-path Packages/Transport TransportDemo
//
// Pass --mock to run without Docker (deterministic in-process data):
//   swift run --package-path Packages/Transport TransportDemo --mock

let useMock = CommandLine.arguments.contains("--mock")
let transport: any TransportClient = useMock ? MockTransport(scenario: .turtlesim) : RosbridgeTransport()
let url = URL(string: "ws://localhost:9090")!
let topic = "/turtle1/pose"

// Observe state transitions in the background.
let stateTask = Task {
    for await state in transport.state {
        print("  [state] \(state)")
    }
}

do {
    print("Connecting to \(useMock ? "mock" : url.absoluteString) …")
    try await transport.connect(url: url)

    // Advertises arrive just after the handshake; give them a beat.
    try? await Task.sleep(for: .milliseconds(800))

    let topics = try await transport.listTopics()
    print("\nTopics (\(topics.count)):")
    for t in topics { print("  \(t.name)  —  \(t.schemaName) [\(t.schemaEncoding)]") }

    print("\nSubscribing to \(topic), printing 10 messages …")
    let stream = try await transport.subscribe(topic)
    var count = 0
    for await message in stream {
        count += 1
        print("  #\(count)  \(message.topic)  ts=\(message.timestamp)  \(message.payload.count) bytes")
        if count >= 10 { break }
    }

    try await transport.unsubscribe(topic)
    await transport.disconnect()
    print("\nDone — received \(count) messages, disconnected cleanly.")
} catch {
    print("\nERROR: \(error)")
    print("Is rosbridge up?  cd app/testing/sim-bot && docker compose up -d")
    print("Or run without Docker:  swift run --package-path Packages/Transport TransportDemo --mock")
    await transport.disconnect()
}

stateTask.cancel()
