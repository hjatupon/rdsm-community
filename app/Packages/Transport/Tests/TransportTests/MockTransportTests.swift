import Foundation
import Testing
@testable import Transport

@Suite("MockTransport lifecycle & delivery")
struct MockTransportTests {
    let url = URL(string: "ws://localhost:8765")!

    @Test
    func `connect emits connecting then connected`() async throws {
        let transport = MockTransport(scenario: .turtlesim)
        try await transport.connect(url: url)
        var labels: [String] = []
        for await state in transport.state {
            switch state {
            case .connecting: labels.append("connecting")
            case .connected: labels.append("connected")
            default: labels.append("other")
            }
            if labels.count >= 2 { break }
        }
        #expect(labels == ["connecting", "connected"])
        await transport.disconnect()
    }

    @Test
    func `listTopics returns the scenario topics`() async throws {
        let transport = MockTransport(scenario: .turtlesim)
        try await transport.connect(url: url)
        let topics = try await transport.listTopics()
        #expect(topics.map(\.name) == ["/rosout", "/turtle1/cmd_vel", "/turtle1/pose"])
        await transport.disconnect()
    }

    @Test
    func `listTopics before connect throws notConnected`() async {
        let transport = MockTransport(scenario: .turtlesim)
        await #expect(throws: TransportError.notConnected) {
            _ = try await transport.listTopics()
        }
    }

    @Test
    func `subscribe delivers messages in per-topic order`() async throws {
        let transport = MockTransport(scenario: .turtlesim)
        try await transport.connect(url: url)
        let stream = try await transport.subscribe("/turtle1/pose")
        var timestamps: [UInt64] = []
        for await message in stream {
            #expect(message.topic == "/turtle1/pose")
            timestamps.append(message.timestamp)
            if timestamps.count >= 5 { break }
        }
        #expect(timestamps == [0, 1, 2, 3, 4]) // monotonic, in order
        await transport.disconnect()
    }

    @Test
    func `subscribe to unknown topic throws`() async throws {
        let transport = MockTransport(scenario: .turtlesim)
        try await transport.connect(url: url)
        await #expect(throws: TransportError.self) {
            _ = try await transport.subscribe("/does/not/exist")
        }
        await transport.disconnect()
    }

    @Test
    func `empty scenario advertises nothing`() async throws {
        let transport = MockTransport(scenario: .empty)
        try await transport.connect(url: url)
        #expect(try await transport.listTopics().isEmpty)
        await transport.disconnect()
    }

    @Test
    func `write-path operations throw unsupportedOperation`() async {
        let transport = MockTransport(scenario: .turtlesim)
        await #expect(throws: TransportError.unsupportedOperation("advertise")) {
            try await transport.advertise(topic: "/x", schema: "y")
        }
        await #expect(throws: TransportError.unsupportedOperation("publish")) {
            try await transport.publish(TopicMessage(topic: "/x", timestamp: 0, schemaName: "y", payload: Data()))
        }
        await #expect(throws: TransportError.unsupportedOperation("getParameters")) {
            _ = try await transport.getParameters(node: "/n")
        }
        await #expect(throws: TransportError.unsupportedOperation("setParameter")) {
            try await transport.setParameter(Parameter(name: "p", value: .int(1)))
        }
    }

    @Test
    func `shared instance is Sendable across a TaskGroup`() async throws {
        let transport = MockTransport(scenario: .turtlesim)
        try await transport.connect(url: url)
        try await withThrowingTaskGroup(of: Int.self) { group in
            for topic in ["/turtle1/pose", "/turtle1/cmd_vel", "/rosout"] {
                group.addTask {
                    let stream = try await transport.subscribe(topic)
                    var n = 0
                    for await _ in stream {
                        n += 1
                        if n >= 3 { break }
                    }
                    return n
                }
            }
            var total = 0
            for try await n in group {
                total += n
            }
            #expect(total == 9)
        }
        await transport.disconnect()
    }
}
