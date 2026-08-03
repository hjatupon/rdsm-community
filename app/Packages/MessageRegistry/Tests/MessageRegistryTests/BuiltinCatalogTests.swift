import Testing
import Foundation
@testable import MessageRegistry

@Suite("Builtin catalog")
struct BuiltinCatalogTests {

    private static func makeRegistry() -> DefaultMessageRegistry {
        let registry = DefaultMessageRegistry()
        BuiltinSchemas().loadAll(into: registry)
        registry.freeze()
        return registry
    }

    @Test func atLeast100SchemasLoad() {
        let registry = Self.makeRegistry()
        #expect(registry.allSchemas().count >= 100)
    }

    @Test func poseIsPresent() {
        let registry = Self.makeRegistry()
        let schema = registry.schema(for: "geometry_msgs/msg/Pose")
        #expect(schema != nil)
        #expect(schema?.messageName == "Pose")
        #expect(schema?.fields.count == 2)  // position + orientation
    }

    @Test func twistIsPresent() {
        let registry = Self.makeRegistry()
        let schema = registry.schema(for: "geometry_msgs/msg/Twist")
        #expect(schema != nil)
        #expect(schema?.fields.count == 2)  // linear + angular
    }

    @Test func imuIsPresent() {
        let registry = Self.makeRegistry()
        let schema = registry.schema(for: "sensor_msgs/msg/Imu")
        #expect(schema != nil)
    }

    @Test func pointCloud2IsPresent() {
        let registry = Self.makeRegistry()
        let schema = registry.schema(for: "sensor_msgs/msg/PointCloud2")
        #expect(schema != nil)
        // Spot check a field
        let hasData = schema?.fields.contains(where: { $0.name == "data" }) ?? false
        #expect(hasData)
    }

    @Test func shortNameAlsoResolves() {
        let registry = Self.makeRegistry()
        let byFull = registry.schema(for: "geometry_msgs/msg/Pose")
        let byShort = registry.schema(for: "geometry_msgs/Pose")
        #expect(byFull != nil)
        #expect(byShort?.fullName == byFull?.fullName)
    }

    @Test func allSchemasHaveValidFullNames() {
        let registry = Self.makeRegistry()
        for schema in registry.allSchemas() {
            #expect(schema.fullName.contains("/msg/"))
        }
    }

    @Test func laserScanIsPresent() {
        let registry = Self.makeRegistry()
        #expect(registry.schema(for: "sensor_msgs/msg/LaserScan") != nil)
    }

    @Test func tf2MessageIsPresent() {
        let registry = Self.makeRegistry()
        #expect(registry.schema(for: "tf2_msgs/msg/TFMessage") != nil)
    }
}
