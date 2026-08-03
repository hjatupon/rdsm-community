import Foundation
import ProfileStore

@main
struct ProfileDemo {
    static func main() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("profiledemo-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tmp) }

        let store = ProfileStore(databaseURL: tmp)

        let robot1 = ConnectionProfile(name: "Spot (Lab)", url: URL(string: "ws://192.168.1.10:8765")!)
        let robot2 = ConnectionProfile(name: "Arm (Cell 3)", url: URL(string: "ws://10.0.0.42:8765")!)

        try await store.save(robot1)
        try await store.save(robot2)

        print("After save:")
        for p in await store.list() { print("  \(p.name)  \(p.url)") }

        try await store.delete(robot1.id)
        print("After delete:")
        for p in await store.list() { print("  \(p.name)  \(p.url)") }
        print("Done.")
    }
}
