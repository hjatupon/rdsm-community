import Testing
import Foundation
@testable import MessageRegistry

@Suite("Concurrency")
struct ConcurrencyTests {

    @Test func concurrentSchemaLookup() async {
        let registry = DefaultMessageRegistry()
        BuiltinSchemas().loadAll(into: registry)
        registry.freeze()

        // 1000 concurrent lookups across multiple tasks — ThreadSanitizer should be clean.
        await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<1000 {
                group.addTask {
                    registry.schema(for: "geometry_msgs/msg/Pose") != nil
                }
            }
            var results: [Bool] = []
            for await result in group { results.append(result) }
            #expect(results.allSatisfy { $0 })
        }
    }

    @Test func registerAndFreezeRace() async {
        // Rapidly register + freeze on the same registry, then read.
        // This validates the NSLock protection under contention.
        let registry = DefaultMessageRegistry()
        let builtins = BuiltinSchemas()

        // Load schemas on a background task while we freeze on the main flow.
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                builtins.loadAll(into: registry)
            }
            group.addTask {
                // Small delay to interleave, then freeze
                try? await Task.sleep(for: .milliseconds(1))
                registry.freeze()
            }
        }

        // After both tasks complete the registry is either partially or fully populated,
        // but must not have crashed or deadlocked.
        let count = registry.allSchemas().count
        #expect(count >= 0)  // Just assert no crash
    }
}
