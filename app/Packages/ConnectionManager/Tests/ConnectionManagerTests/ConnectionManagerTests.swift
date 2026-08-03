import Testing
import Foundation
@testable import ConnectionManager
import Transport

// MARK: - Helpers

private let mockURL1 = URL(string: "ws://localhost:8765")!
private let mockURL2 = URL(string: "ws://localhost:8766")!
private let mockURL3 = URL(string: "ws://localhost:8767")!

private actor SnapshotCollector {
    var snapshots: [[ConnectionHandle]] = []
    func append(_ s: [ConnectionHandle]) { snapshots.append(s) }
}

private func makeManager() -> ConnectionManager {
    ConnectionManager(transportFactory: { _ in MockTransport(scenario: .empty) })
}

private func profile(_ url: URL, name: String = "test") -> ConnectionProfile {
    ConnectionProfile(name: name, url: url)
}

// MARK: - Lifecycle tests

@Suite("LifecycleTests")
struct LifecycleTests {

    @Test("connect returns a handle with the given profile URL")
    func testConnectReturnsHandle() async throws {
        let mgr = makeManager()
        let p = profile(mockURL1)
        let handle = try await mgr.connect(p)
        #expect(handle.profile.url == mockURL1)
    }

    @Test("handle appears in activeHandles after connect")
    func testHandleInActiveHandles() async throws {
        let mgr = makeManager()
        let handle = try await mgr.connect(profile(mockURL1))
        let active = await mgr.activeHandles
        #expect(active.contains(handle))
    }

    @Test("handle disappears from activeHandles after disconnect")
    func testDisconnectRemovesHandle() async throws {
        let mgr = makeManager()
        let handle = try await mgr.connect(profile(mockURL1))
        try await mgr.disconnect(handle)
        let active = await mgr.activeHandles
        #expect(!active.contains(handle))
    }

    @Test("activeHandles is empty after disconnecting all")
    func testAllDisconnected() async throws {
        let mgr = makeManager()
        let h1 = try await mgr.connect(profile(mockURL1, name: "a"))
        let h2 = try await mgr.connect(profile(mockURL2, name: "b"))
        try await mgr.disconnect(h1)
        try await mgr.disconnect(h2)
        let active = await mgr.activeHandles
        #expect(active.isEmpty)
    }

    @Test("connections stream emits on connect")
    func testConnectionsStreamEmitsOnConnect() async throws {
        let mgr = makeManager()
        let collector = SnapshotCollector()
        let task = Task {
            for await snapshot in await mgr.connections {
                await collector.append(snapshot)
                if await collector.snapshots.count >= 1 { break }
            }
        }
        _ = try await mgr.connect(profile(mockURL1))
        await task.value
        let snapshots = await collector.snapshots
        #expect(!snapshots.isEmpty)
        #expect(snapshots.last?.count == 1)
    }

    @Test("connections stream emits on disconnect")
    func testConnectionsStreamEmitsOnDisconnect() async throws {
        let mgr = makeManager()
        let collector = SnapshotCollector()
        let task = Task {
            for await snapshot in await mgr.connections {
                await collector.append(snapshot)
                if await collector.snapshots.count >= 2 { break }
            }
        }
        let h = try await mgr.connect(profile(mockURL1))
        try await mgr.disconnect(h)
        await task.value
        let snapshots = await collector.snapshots
        #expect(snapshots.count == 2)
        #expect(snapshots[0].count == 1)
        #expect(snapshots[1].isEmpty)
    }
}

// MARK: - Dedup tests

@Suite("DedupTests")
struct DedupTests {

    @Test("connecting to the same URL twice throws alreadyConnected")
    func testDuplicateConnectThrows() async throws {
        let mgr = makeManager()
        _ = try await mgr.connect(profile(mockURL1))
        do {
            _ = try await mgr.connect(profile(mockURL1, name: "duplicate"))
            Issue.record("Expected alreadyConnected to be thrown")
        } catch let err as ConnectionManagerError {
            if case .alreadyConnected(let url) = err {
                #expect(url == mockURL1)
            } else {
                Issue.record("Wrong error: \(err)")
            }
        }
    }

    @Test("can reconnect to same URL after disconnect")
    func testReconnectAfterDisconnect() async throws {
        let mgr = makeManager()
        let h = try await mgr.connect(profile(mockURL1))
        try await mgr.disconnect(h)
        let h2 = try await mgr.connect(profile(mockURL1, name: "reconnect"))
        #expect(h2.profile.url == mockURL1)
    }

    @Test("different URLs can connect simultaneously")
    func testDifferentURLsAllowed() async throws {
        let mgr = makeManager()
        let h1 = try await mgr.connect(profile(mockURL1, name: "a"))
        let h2 = try await mgr.connect(profile(mockURL2, name: "b"))
        let h3 = try await mgr.connect(profile(mockURL3, name: "c"))
        let active = await mgr.activeHandles
        #expect(active.count == 3)
        #expect(active.contains(h1))
        #expect(active.contains(h2))
        #expect(active.contains(h3))
    }
}

// MARK: - Disconnect error tests

@Suite("DisconnectErrorTests")
struct DisconnectErrorTests {

    @Test("disconnecting unknown handle throws unknownHandle")
    func testUnknownHandleThrows() async throws {
        let mgr = makeManager()
        let ghost = ConnectionHandle(
            id: UUID(),
            profile: profile(mockURL1),
            transport: MockTransport(scenario: .empty))
        do {
            try await mgr.disconnect(ghost)
            Issue.record("Expected unknownHandle to be thrown")
        } catch let err as ConnectionManagerError {
            if case .unknownHandle = err {
                // expected
            } else {
                Issue.record("Wrong error: \(err)")
            }
        }
    }
}

// MARK: - ReconnectAll tests

@Suite("ReconnectAllTests")
struct ReconnectAllTests {

    @Test("reconnectAll restores the same number of connections")
    func testReconnectAllRestoresCount() async throws {
        let mgr = makeManager()
        _ = try await mgr.connect(profile(mockURL1, name: "a"))
        _ = try await mgr.connect(profile(mockURL2, name: "b"))
        await mgr.reconnectAll()
        let active = await mgr.activeHandles
        #expect(active.count == 2)
    }

    @Test("reconnectAll on empty manager is a no-op")
    func testReconnectAllEmpty() async {
        let mgr = makeManager()
        await mgr.reconnectAll()
        let active = await mgr.activeHandles
        #expect(active.isEmpty)
    }
}

// MARK: - Profile store tests

@Suite("ProfileStoreTests")
struct ProfileStoreTests {

    @Test("saveProfiles and loadedProfiles round-trip")
    func testProfileRoundTrip() async throws {
        let mgr = makeManager()
        let profiles = [
            profile(mockURL1, name: "robot1"),
            profile(mockURL2, name: "robot2"),
        ]
        await mgr.saveProfiles(profiles)
        let loaded = await mgr.loadedProfiles()
        #expect(loaded.map(\.name) == ["robot1", "robot2"])
    }
}

// MARK: - Leak test

@Suite("LeakTests")
struct LeakTests {

    @Test("connect then disconnect returns to zero active handles")
    func testNoHandleLeak() async throws {
        let mgr = makeManager()
        for i in 0..<5 {
            let url = URL(string: "ws://localhost:\(8800 + i)")!
            let h = try await mgr.connect(profile(url, name: "r\(i)"))
            try await mgr.disconnect(h)
        }
        let active = await mgr.activeHandles
        #expect(active.isEmpty)
    }
}
