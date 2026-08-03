import Testing
import Foundation
@testable import InspectorUI

// MARK: - RenderKindResolver tests

@Suite("RenderKindResolverTests")
struct RenderKindResolverTests {
    let resolver = RenderKindResolver()

    // MARK: Image

    @Test("sensor_msgs/msg/Image → .image")
    func testImageSchema() {
        #expect(resolver.resolve(schemaName: "sensor_msgs/msg/Image") == .image)
    }

    @Test("sensor_msgs/msg/CompressedImage → .image")
    func testCompressedImage() {
        #expect(resolver.resolve(schemaName: "sensor_msgs/msg/CompressedImage") == .image)
    }

    @Test("image in arbitrary package → .image")
    func testCustomImageSchema() {
        #expect(resolver.resolve(schemaName: "my_msgs/msg/DepthImage") == .image)
    }

    // MARK: Numeric scalar

    @Test("std_msgs/msg/Float64 → .numericScalar")
    func testFloat64() {
        #expect(resolver.resolve(schemaName: "std_msgs/msg/Float64") == .numericScalar)
    }

    @Test("std_msgs/msg/Float32 → .numericScalar")
    func testFloat32() {
        #expect(resolver.resolve(schemaName: "std_msgs/msg/Float32") == .numericScalar)
    }

    @Test("std_msgs/msg/Int32 → .numericScalar")
    func testInt32() {
        #expect(resolver.resolve(schemaName: "std_msgs/msg/Int32") == .numericScalar)
    }

    @Test("std_msgs/msg/Int64 → .numericScalar")
    func testInt64() {
        #expect(resolver.resolve(schemaName: "std_msgs/msg/Int64") == .numericScalar)
    }

    @Test("std_msgs/msg/UInt8 → .numericScalar")
    func testUInt8() {
        #expect(resolver.resolve(schemaName: "std_msgs/msg/UInt8") == .numericScalar)
    }

    @Test("std_msgs/msg/Bool → .numericScalar")
    func testBool() {
        #expect(resolver.resolve(schemaName: "std_msgs/msg/Bool") == .numericScalar)
    }

    // MARK: JSON tree (everything else)

    @Test("geometry_msgs/msg/Pose → .jsonTree")
    func testPose() {
        #expect(resolver.resolve(schemaName: "geometry_msgs/msg/Pose") == .jsonTree)
    }

    @Test("sensor_msgs/msg/Imu → .jsonTree")
    func testImu() {
        #expect(resolver.resolve(schemaName: "sensor_msgs/msg/Imu") == .jsonTree)
    }

    @Test("nav_msgs/msg/Odometry → .jsonTree")
    func testOdometry() {
        #expect(resolver.resolve(schemaName: "nav_msgs/msg/Odometry") == .jsonTree)
    }

    @Test("rcl_interfaces/msg/Log → .jsonTree")
    func testLog() {
        #expect(resolver.resolve(schemaName: "rcl_interfaces/msg/Log") == .jsonTree)
    }

    @Test("empty schema → .jsonTree")
    func testEmptySchema() {
        #expect(resolver.resolve(schemaName: "") == .jsonTree)
    }

    @Test("unknown schema → .jsonTree")
    func testUnknownSchema() {
        #expect(resolver.resolve(schemaName: "custom_msgs/msg/Mystery") == .jsonTree)
    }
}

// MARK: - FieldNode tests

@Suite("FieldNodeTests")
struct FieldNodeTests {

    @Test("leaf node has no children")
    func testLeaf() {
        let node = FieldNode(key: "x", displayValue: "1.0")
        #expect(node.isLeaf)
        #expect(node.children.isEmpty)
    }

    @Test("container node has children")
    func testContainer() {
        let child = FieldNode(key: "x", displayValue: "1.0")
        let node = FieldNode(key: "position", displayValue: "{…}", children: [child])
        #expect(!node.isLeaf)
        #expect(node.children.count == 1)
    }

    @Test("from(key:value:) with Double produces leaf")
    func testFromDouble() {
        let node = FieldNode.from(key: "x", value: 3.14)
        #expect(node.isLeaf)
        #expect(node.displayValue.contains("3.14"))
    }

    @Test("from(key:value:) with dict produces container")
    func testFromDict() {
        let node = FieldNode.from(key: "position", value: ["x": 1.0, "y": 2.0, "z": 3.0])
        #expect(!node.isLeaf)
        #expect(node.children.count == 3)
    }

    @Test("from(key:value:) with array produces indexed children")
    func testFromArray() {
        let node = FieldNode.from(key: "points", value: [1.0, 2.0, 3.0])
        #expect(!node.isLeaf)
        #expect(node.children[0].key == "[0]")
        #expect(node.children[1].key == "[1]")
    }

    @Test("from(key:value:) with empty array produces leaf")
    func testFromEmptyArray() {
        let node = FieldNode.from(key: "data", value: [Any]())
        #expect(node.isLeaf)
        #expect(node.displayValue == "[]")
    }

    @Test("fromJSON parses flat dict")
    func testFromJSONFlat() throws {
        let json = """
        {"x": 1.0, "y": 2.0}
        """.data(using: .utf8)!
        let roots = FieldNode.fromJSON(json)
        #expect(roots.count == 2)
        #expect(Set(roots.map(\.key)) == ["x", "y"])
    }

    @Test("fromJSON parses nested dict")
    func testFromJSONNested() throws {
        let json = """
        {"position": {"x": 1.0, "y": 2.0, "z": 3.0}}
        """.data(using: .utf8)!
        let roots = FieldNode.fromJSON(json)
        #expect(roots.count == 1)
        #expect(roots[0].key == "position")
        #expect(roots[0].children.count == 3)
    }

    @Test("fromJSON with invalid data returns raw fallback")
    func testFromJSONInvalid() {
        let data = "not json".data(using: .utf8)!
        let roots = FieldNode.fromJSON(data)
        #expect(roots.count == 1)
        #expect(roots[0].key == "(raw)")
    }

    @Test("fromJSON with bool leaf shows true/false")
    func testBoolLeaf() throws {
        let json = #"{"active": true}"#.data(using: .utf8)!
        let roots = FieldNode.fromJSON(json)
        let node = roots.first { $0.key == "active" }
        #expect(node?.displayValue == "true")
    }

    @Test("fromJSON children sorted alphabetically")
    func testSortedKeys() throws {
        let json = #"{"z": 3, "a": 1, "m": 2}"#.data(using: .utf8)!
        let roots = FieldNode.fromJSON(json)
        #expect(roots.map(\.key) == ["a", "m", "z"])
    }
}
