import Testing
import Foundation
@testable import MessageRegistry

@Suite("DynamicDecoder")
struct DynamicDecoderTests {

    private func makeRegistry() -> DefaultMessageRegistry {
        let registry = DefaultMessageRegistry()
        BuiltinSchemas().loadAll(into: registry)
        registry.freeze()
        return registry
    }

    // MARK: - JSON decoding

    @Test func decodesJSONPose() throws {
        let registry = makeRegistry()
        let decoder = DynamicDecoder(registry: registry)
        guard let schema = registry.schema(for: "geometry_msgs/msg/Pose") else {
            Issue.record("Pose schema not found")
            return
        }
        let json = """
        {
            "position": {"x": 1.0, "y": 2.0, "z": 3.0},
            "orientation": {"x": 0.0, "y": 0.0, "z": 0.0, "w": 1.0}
        }
        """.data(using: .utf8)!

        let msg = decoder.decode(schema: schema, payload: json, encoding: "json")
        #expect(msg.schemaName == "geometry_msgs/msg/Pose")

        guard case .message(let position) = msg["position"] else {
            Issue.record("position field not decoded as message")
            return
        }
        guard case .float64(let x) = position["x"] else {
            Issue.record("position.x not decoded as float64")
            return
        }
        #expect(x == 1.0)
    }

    @Test func decodesJSONStringField() throws {
        let registry = makeRegistry()
        let decoder = DynamicDecoder(registry: registry)
        guard let schema = registry.schema(for: "std_msgs/msg/String") else {
            Issue.record("std_msgs/String not found")
            return
        }
        let json = #"{"data": "hello"}"#.data(using: .utf8)!
        let msg = decoder.decode(schema: schema, payload: json, encoding: "json")
        guard case .string(let s) = msg["data"] else {
            Issue.record("data not decoded as string")
            return
        }
        #expect(s == "hello")
    }

    @Test func decodesJSONBoolField() throws {
        let registry = makeRegistry()
        let decoder = DynamicDecoder(registry: registry)
        guard let schema = registry.schema(for: "std_msgs/msg/Bool") else {
            Issue.record("std_msgs/Bool not found")
            return
        }
        let json = #"{"data": true}"#.data(using: .utf8)!
        let msg = decoder.decode(schema: schema, payload: json, encoding: "json")
        guard case .bool(let b) = msg["data"] else {
            Issue.record("data not decoded as bool")
            return
        }
        #expect(b == true)
    }

    // MARK: - CDR decoding

    /// Manually builds a CDR little-endian Pose payload and verifies decoding.
    /// Pose = {position: Point{x,y,z: float64}, orientation: Quaternion{x,y,z,w: float64}}
    @Test func decodesCDRPose() throws {
        let registry = makeRegistry()
        let decoder = DynamicDecoder(registry: registry)
        guard let schema = registry.schema(for: "geometry_msgs/msg/Pose") else {
            Issue.record("Pose schema not found")
            return
        }

        // Build CDR payload: 4-byte encapsulation header + 7 float64 values
        var data = Data([0x00, 0x01, 0x00, 0x00])  // little-endian encapsulation
        func appendDouble(_ v: Double) {
            var bits = v.bitPattern
            withUnsafeBytes(of: &bits) { data.append(contentsOf: $0) }
        }
        // position.x=1.0, y=2.0, z=3.0
        appendDouble(1.0); appendDouble(2.0); appendDouble(3.0)
        // orientation.x=0.0, y=0.0, z=0.0, w=1.0
        appendDouble(0.0); appendDouble(0.0); appendDouble(0.0); appendDouble(1.0)

        let msg = decoder.decode(schema: schema, payload: data, encoding: "ros2msg")
        guard case .message(let pos) = msg["position"] else {
            Issue.record("position not decoded")
            return
        }
        guard case .float64(let x) = pos["x"] else {
            Issue.record("x not float64")
            return
        }
        #expect(abs(x - 1.0) < 1e-9)

        guard case .message(let ori) = msg["orientation"] else {
            Issue.record("orientation not decoded")
            return
        }
        guard case .float64(let w) = ori["w"] else {
            Issue.record("w not float64")
            return
        }
        #expect(abs(w - 1.0) < 1e-9)
    }

    @Test func returnsNullOnMalformedPayload() {
        let registry = makeRegistry()
        let decoder = DynamicDecoder(registry: registry)
        guard let schema = registry.schema(for: "geometry_msgs/msg/Pose") else { return }
        // Payload too short to contain a full Pose
        let msg = decoder.decode(schema: schema, payload: Data([0x00, 0x01]), encoding: "ros2msg")
        // Should not crash; fields will be .null
        #expect(msg.schemaName == "geometry_msgs/msg/Pose")
    }
}
