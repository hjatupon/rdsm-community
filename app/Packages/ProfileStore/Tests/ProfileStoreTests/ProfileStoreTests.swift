import Testing
import Foundation
@testable import ProfileStore

// MARK: - Helpers

private func makeStore() -> (ProfileStore, URL) {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("ps-test-\(UUID().uuidString).json")
    return (ProfileStore(databaseURL: url), url)
}

private func profile(_ name: String, urlString: String = "ws://localhost:8765") -> ConnectionProfile {
    ConnectionProfile(name: name, url: URL(string: urlString)!)
}

// MARK: - CRUD tests

@Suite("CRUDTests")
struct CRUDTests {

    @Test("list() returns empty on a fresh store")
    func testEmptyList() async {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url) }
        let result = await store.list()
        #expect(result.isEmpty)
    }

    @Test("save then list round-trips name and URL")
    func testSaveAndList() async throws {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url) }
        let p = profile("Robot A")
        try await store.save(p)
        let loaded = await store.list()
        #expect(loaded.count == 1)
        #expect(loaded[0].name == "Robot A")
        #expect(loaded[0].url == p.url)
    }

    @Test("save with same id replaces the existing profile")
    func testSaveUpdates() async throws {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url) }
        var p = profile("Initial")
        try await store.save(p)
        p = ConnectionProfile(id: p.id, name: "Updated", url: p.url)
        try await store.save(p)
        let loaded = await store.list()
        #expect(loaded.count == 1)
        #expect(loaded[0].name == "Updated")
    }

    @Test("delete removes the profile")
    func testDelete() async throws {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url) }
        let p = profile("Robot B")
        try await store.save(p)
        try await store.delete(p.id)
        let loaded = await store.list()
        #expect(loaded.isEmpty)
    }

    @Test("delete unknown id throws profileNotFound")
    func testDeleteUnknownThrows() async throws {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url) }
        let id = UUID()
        do {
            try await store.delete(id)
            Issue.record("Expected profileNotFound")
        } catch let err as ProfileStoreError {
            if case .profileNotFound(let found) = err {
                #expect(found == id)
            } else {
                Issue.record("Wrong error: \(err)")
            }
        }
    }

    @Test("list() returns profiles sorted by name")
    func testListSorted() async throws {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url) }
        try await store.save(profile("Zephyr"))
        try await store.save(profile("Alpha"))
        try await store.save(profile("Mango"))
        let names = await store.list().map(\.name)
        #expect(names == ["Alpha", "Mango", "Zephyr"])
    }

    @Test("multiple profiles persist correctly")
    func testMultipleProfiles() async throws {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url) }
        for i in 0..<5 {
            try await store.save(profile("Robot \(i)", urlString: "ws://localhost:\(8000+i)"))
        }
        let loaded = await store.list()
        #expect(loaded.count == 5)
    }
}

// MARK: - Persistence tests

@Suite("PersistenceTests")
struct PersistenceTests {

    @Test("data survives a second store instance pointing at the same file")
    func testPersistsAcrossInstances() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ps-persist-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store1 = ProfileStore(databaseURL: url)
        try await store1.save(profile("Persisted Bot"))

        let store2 = ProfileStore(databaseURL: url)
        let loaded = await store2.list()
        #expect(loaded.count == 1)
        #expect(loaded[0].name == "Persisted Bot")
    }
}
