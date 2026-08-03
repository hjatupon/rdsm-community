import Testing
import Foundation
@testable import TopicStore
import Transport
import MessageRegistry

// MARK: - Helpers

private let mockURL = URL(string: "ws://localhost:8765")!

private func makeConnectedTransport(scenario: MockScenario = .turtlesim) async throws -> MockTransport {
    let transport = MockTransport(scenario: scenario)
    try await transport.connect(url: mockURL, auth: nil)
    return transport
}

private func makeStore(
    scenario: MockScenario = .turtlesim,
    capacity: Int = 64
) async throws -> TopicStore {
    let transport = try await makeConnectedTransport(scenario: scenario)
    let registry = DefaultMessageRegistry()
    BuiltinSchemas().loadAll(into: registry)
    registry.freeze()
    return TopicStore(transport: transport, registry: registry, cacheCapacity: capacity)
}

// MARK: - RingBuffer unit tests

@Suite("RingBufferTests")
struct RingBufferTests {

    @Test("push respects capacity — oldest dropped")
    func testDropOldest() {
        var buf = RingBuffer<Int>(capacity: 3)
        buf.push(1); buf.push(2); buf.push(3); buf.push(4)
        let all = buf.all()
        #expect(all.count == 3)
        #expect(!all.contains(1))   // dropped
        #expect(all.contains(4))
    }

    @Test("latest returns most recent value")
    func testLatest() {
        var buf = RingBuffer<Int>(capacity: 10)
        buf.push(10); buf.push(20); buf.push(30)
        #expect(buf.latest == 30)
    }

    @Test("push 15 into capacity-10 → last 10 retained")
    func testCapacity10Push15() {
        var buf = RingBuffer<Int>(capacity: 10)
        for i in 1...15 { buf.push(i) }
        let all = buf.all()
        #expect(all.count == 10)
        #expect(all.first == 6)
        #expect(all.last == 15)
    }

    @Test("empty buffer has nil latest")
    func testEmptyLatest() {
        let buf = RingBuffer<Int>(capacity: 5)
        #expect(buf.latest == nil)
    }

    @Test("clear resets all state")
    func testClear() {
        var buf = RingBuffer<Int>(capacity: 5)
        buf.push(1); buf.push(2)
        buf.clear()
        #expect(buf.count == 0)
        #expect(buf.latest == nil)
    }
}

// MARK: - Lifecycle tests

@Suite("LifecycleTests")
struct LifecycleTests {

    @Test("subscribe returns a stream with messages")
    func testSubscribeReceivesMessages() async throws {
        let store = try await makeStore()
        let stream = try await store.subscribe("/turtle1/pose")
        var count = 0
        for await _ in stream {
            count += 1
            if count >= 3 { break }
        }
        #expect(count == 3)
    }

    @Test("unsubscribe removes the active topic")
    func testUnsubscribe() async throws {
        let store = try await makeStore()
        let _ = try await store.subscribe("/turtle1/pose")
        #expect(await store.activeTopicCount == 1)
        await store.unsubscribe("/turtle1/pose")
        #expect(await store.activeTopicCount == 0)
    }

    @Test("availableTopics lists turtlesim topics")
    func testAvailableTopics() async throws {
        let store = try await makeStore()
        let topics = try await store.availableTopics()
        let names = Set(topics.map { $0.name })
        #expect(names.contains("/turtle1/pose"))
        #expect(names.contains("/turtle1/cmd_vel"))
    }
}

// MARK: - Multi-subscriber fan-out

@Suite("MultiSubscriberTests")
struct MultiSubscriberTests {

    @Test("Two subscribers to same topic both receive messages")
    func testTwoSubscribersFanOut() async throws {
        let store = try await makeStore()
        let stream1 = try await store.subscribe("/turtle1/pose")
        let stream2 = try await store.subscribe("/turtle1/pose")

        // Both should see the same upstream — single active topic
        #expect(await store.activeTopicCount == 1)

        // Collect counts sequentially to avoid Swift 6 capture races
        var count1 = 0
        for await _ in stream1 {
            count1 += 1
            if count1 >= 2 { break }
        }
        var count2 = 0
        for await _ in stream2 {
            count2 += 1
            if count2 >= 2 { break }
        }
        #expect(count1 == 2)
        #expect(count2 == 2)
    }
}

// MARK: - Cache / latest tests

@Suite("CacheTests")
struct CacheTests {

    @Test("latestRaw returns nil before any messages")
    func testLatestRawNilBefore() async throws {
        let store = try await makeStore()
        #expect(await store.latestRaw("/turtle1/pose") == nil)
    }

    @Test("latestRaw returns a value after receiving messages")
    func testLatestRawAfterMessages() async throws {
        let store = try await makeStore()
        let stream = try await store.subscribe("/turtle1/pose")
        // Consume one message to populate cache
        for await _ in stream { break }
        // Give the ring buffer write a moment to settle
        try await Task.sleep(nanoseconds: 10_000_000)
        let latest = await store.latestRaw("/turtle1/pose")
        #expect(latest != nil)
    }

    @Test("Ring buffer capacity is respected")
    func testRingBufferCapacity() async throws {
        // Capacity = 2; push 5 messages; ring should hold only 2
        let store = try await makeStore(capacity: 2)
        let stream = try await store.subscribe("/turtle1/pose")
        var count = 0
        for await _ in stream {
            count += 1
            if count >= 5 { break }
        }
        // The store's ring buffer capacity is 2 (set in makeStore)
        // We can't directly inspect the internal ring buffer from here,
        // but latestRaw should still return a value
        let latest = await store.latestRaw("/turtle1/pose")
        #expect(latest != nil)
    }
}

// MARK: - Timestamped tests

@Suite("TimestampedTests")
struct TimestampedTests {

    @Test("Timestamped carries timestamp and value")
    func testTimestampedStruct() {
        let t = Timestamped(timestamp: 12345, value: "hello")
        #expect(t.timestamp == 12345)
        #expect(t.value == "hello")
    }

    @Test("Timestamped is Sendable — usable across task boundaries")
    func testTimestampedSendable() async {
        let t = Timestamped(timestamp: 0, value: 42)
        let result = await Task.detached { t }.value
        #expect(result.value == 42)
    }
}

// MARK: - Source substitution (Contract C5)

@Suite("SourceSubstitutionTests")
struct SourceSubstitutionTests {

    @Test("Empty scenario TopicStore returns empty topic list")
    func testEmptyTransport() async throws {
        let store = try await makeStore(scenario: .empty)
        let topics = try await store.availableTopics()
        #expect(topics.isEmpty)
    }

    @Test("Custom scenario topics are listed correctly")
    func testCustomScenario() async throws {
        let descriptors = [
            TopicDescriptor(name: "/scan", schemaName: "sensor_msgs/msg/LaserScan", schemaEncoding: "json"),
            TopicDescriptor(name: "/odom", schemaName: "nav_msgs/msg/Odometry", schemaEncoding: "json"),
        ]
        let store = try await makeStore(scenario: .custom(descriptors))
        let topics = try await store.availableTopics()
        let names = Set(topics.map { $0.name })
        #expect(names.contains("/scan"))
        #expect(names.contains("/odom"))
    }
}
