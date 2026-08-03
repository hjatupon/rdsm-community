import Foundation
import LayoutEngine

@main
struct LayoutDemo {
    static func main() async throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("layoutdemo-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: base) }

        let engine = LayoutEngine(localURL: base)

        let panel1 = PanelState(panelType: "topicBrowser",
                                frame: LayoutRect(x: 0, y: 0, width: 300, height: 600))
        let panel2 = PanelState(panelType: "viewer3d",
                                frame: LayoutRect(x: 300, y: 0, width: 980, height: 600))
        let layout = LayoutState(panels: [panel1, panel2],
                                 windowFrame: LayoutRect(x: 50, y: 50, width: 1280, height: 800),
                                 sidebarWidth: 300)

        try await engine.save(layout, named: "default")
        try await engine.save(LayoutState(), named: "minimal")

        print("Saved layouts:", await engine.list())

        let loaded = try await engine.load(named: "default")
        print("Loaded: version=\(loaded.version) panels=\(loaded.panels.count) sidebar=\(loaded.sidebarWidth)")

        try await engine.delete(named: "minimal")
        print("After delete:", await engine.list())
        print("Done.")
    }
}
