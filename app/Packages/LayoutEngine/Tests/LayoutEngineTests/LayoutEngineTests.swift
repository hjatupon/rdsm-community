import Testing
import Foundation
@testable import LayoutEngine

// MARK: - Helpers

private func makeEngine() -> (LayoutEngine, URL) {
    let base = FileManager.default.temporaryDirectory
        .appendingPathComponent("le-test-\(UUID().uuidString)")
    return (LayoutEngine(localURL: base), base)
}

private func panel(_ type: String) -> PanelState {
    PanelState(panelType: type, frame: LayoutRect(x: 0, y: 0, width: 100, height: 100))
}

// MARK: - Round-trip tests

@Suite("RoundTripTests")
struct RoundTripTests {

    @Test("save then load returns the same panels")
    func testSaveLoadPanels() async throws {
        let (engine, base) = makeEngine()
        defer { try? FileManager.default.removeItem(at: base) }

        let state = LayoutState(panels: [panel("topicBrowser"), panel("viewer3d")])
        try await engine.save(state, named: "test")
        let loaded = try await engine.load(named: "test")

        #expect(loaded.panels.count == 2)
        #expect(loaded.panels[0].panelType == "topicBrowser")
        #expect(loaded.panels[1].panelType == "viewer3d")
    }

    @Test("save then load preserves windowFrame")
    func testSaveLoadWindowFrame() async throws {
        let (engine, base) = makeEngine()
        defer { try? FileManager.default.removeItem(at: base) }

        let frame = LayoutRect(x: 10, y: 20, width: 1920, height: 1080)
        let state = LayoutState(windowFrame: frame)
        try await engine.save(state, named: "frame-test")
        let loaded = try await engine.load(named: "frame-test")

        #expect(loaded.windowFrame.x == 10)
        #expect(loaded.windowFrame.y == 20)
        #expect(loaded.windowFrame.width == 1920)
        #expect(loaded.windowFrame.height == 1080)
    }

    @Test("save then load preserves sidebarWidth")
    func testSaveLoadSidebarWidth() async throws {
        let (engine, base) = makeEngine()
        defer { try? FileManager.default.removeItem(at: base) }

        let state = LayoutState(sidebarWidth: 320)
        try await engine.save(state, named: "sidebar-test")
        let loaded = try await engine.load(named: "sidebar-test")

        #expect(loaded.sidebarWidth == 320)
    }

    @Test("panel configuration blob round-trips")
    func testPanelConfigurationBlob() async throws {
        let (engine, base) = makeEngine()
        defer { try? FileManager.default.removeItem(at: base) }

        let config = try JSONEncoder().encode(["topicFilter": "/robot/pose"])
        let p = PanelState(panelType: "topicBrowser",
                           frame: LayoutRect(x: 0, y: 0, width: 200, height: 300),
                           configuration: config)
        let state = LayoutState(panels: [p])
        try await engine.save(state, named: "config-test")
        let loaded = try await engine.load(named: "config-test")

        let decoded = try JSONDecoder().decode([String: String].self, from: loaded.panels[0].configuration)
        #expect(decoded["topicFilter"] == "/robot/pose")
    }
}

// MARK: - List / delete tests

@Suite("ListDeleteTests")
struct ListDeleteTests {

    @Test("list returns empty for new engine")
    func testEmptyList() async {
        let (engine, base) = makeEngine()
        defer { try? FileManager.default.removeItem(at: base) }
        let names = await engine.list()
        #expect(names.isEmpty)
    }

    @Test("list returns sorted names after saves")
    func testListSorted() async throws {
        let (engine, base) = makeEngine()
        defer { try? FileManager.default.removeItem(at: base) }

        try await engine.save(LayoutState(), named: "zeta")
        try await engine.save(LayoutState(), named: "alpha")
        try await engine.save(LayoutState(), named: "mango")

        let names = await engine.list()
        #expect(names == ["alpha", "mango", "zeta"])
    }

    @Test("delete removes the layout")
    func testDelete() async throws {
        let (engine, base) = makeEngine()
        defer { try? FileManager.default.removeItem(at: base) }

        try await engine.save(LayoutState(), named: "to-delete")
        try await engine.delete(named: "to-delete")
        let names = await engine.list()
        #expect(names.isEmpty)
    }

    @Test("delete unknown name throws layoutNotFound")
    func testDeleteUnknownThrows() async throws {
        let (engine, base) = makeEngine()
        defer { try? FileManager.default.removeItem(at: base) }

        do {
            try await engine.delete(named: "ghost")
            Issue.record("Expected layoutNotFound")
        } catch let err as LayoutEngineError {
            if case .layoutNotFound(let name) = err {
                #expect(name == "ghost")
            } else {
                Issue.record("Wrong error: \(err)")
            }
        }
    }

    @Test("load unknown name throws layoutNotFound")
    func testLoadUnknownThrows() async throws {
        let (engine, base) = makeEngine()
        defer { try? FileManager.default.removeItem(at: base) }

        do {
            _ = try await engine.load(named: "ghost")
            Issue.record("Expected layoutNotFound")
        } catch let err as LayoutEngineError {
            if case .layoutNotFound = err { /* expected */ } else {
                Issue.record("Wrong error: \(err)")
            }
        }
    }
}

// MARK: - Migration tests

@Suite("MigrationTests")
struct MigrationTests {

    @Test("v1 JSON (no sidebarWidth) migrates to v2 with default 260")
    func testV1ToV2Migration() async throws {
        let (engine, base) = makeEngine()
        defer { try? FileManager.default.removeItem(at: base) }

        // Craft a v1 JSON manually — no sidebarWidth field
        let v1Json = """
        {
            "version": 1,
            "panels": [],
            "windowFrame": {"x": 0, "y": 0, "width": 1280, "height": 800}
        }
        """.data(using: .utf8)!

        let layoutsDir = base.appendingPathComponent("layouts")
        try FileManager.default.createDirectory(at: layoutsDir, withIntermediateDirectories: true)
        try v1Json.write(to: layoutsDir.appendingPathComponent("migrated.json"))

        let loaded = try await engine.load(named: "migrated")
        #expect(loaded.version == 2)
        #expect(loaded.sidebarWidth == 260)
    }

    @Test("v2 JSON loads without migration")
    func testV2NoMigrationNeeded() async throws {
        let (engine, base) = makeEngine()
        defer { try? FileManager.default.removeItem(at: base) }

        let state = LayoutState(sidebarWidth: 400)
        try await engine.save(state, named: "v2-direct")
        let loaded = try await engine.load(named: "v2-direct")
        #expect(loaded.version == 2)
        #expect(loaded.sidebarWidth == 400)
    }
}

// MARK: - Persistence test

@Suite("PersistenceTests")
struct PersistenceTests {

    @Test("data survives a second engine instance pointing at the same directory")
    func testPersistsAcrossInstances() async throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("le-persist-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: base) }

        let engine1 = LayoutEngine(localURL: base)
        try await engine1.save(LayoutState(sidebarWidth: 999), named: "persisted")

        let engine2 = LayoutEngine(localURL: base)
        let loaded = try await engine2.load(named: "persisted")
        #expect(loaded.sidebarWidth == 999)
    }
}
