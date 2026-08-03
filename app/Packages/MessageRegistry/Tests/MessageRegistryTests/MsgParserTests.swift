import Testing
import Foundation
@testable import MessageRegistry

@Suite("MsgParser")
struct MsgParserTests {
    private let parser = MsgParser()

    @Test func parsesSimpleFields() throws {
        let text = """
        float64 x
        float64 y
        float64 z
        """
        let schema = try parser.parse(text, packageName: "geometry_msgs", messageName: "Point")
        #expect(schema.packageName == "geometry_msgs")
        #expect(schema.messageName == "Point")
        #expect(schema.fullName == "geometry_msgs/msg/Point")
        #expect(schema.fields.count == 3)
        #expect(schema.fields[0].name == "x")
        #expect(schema.fields[0].type == .float64)
        #expect(schema.constants.isEmpty)
    }

    @Test func parsesConstants() throws {
        let text = """
        uint8 INT8 = 1
        uint8 UINT8 = 2
        string name
        uint32 value
        """
        let schema = try parser.parse(text, packageName: "test_msgs", messageName: "WithConstants")
        #expect(schema.constants.count == 2)
        #expect(schema.constants[0].name == "INT8")
        #expect(schema.constants[0].rawValue == "1")
        #expect(schema.constants[1].name == "UINT8")
        #expect(schema.fields.count == 2)
    }

    @Test func parsesNestedType() throws {
        let text = """
        geometry_msgs/Point position
        Quaternion orientation
        """
        let schema = try parser.parse(text, packageName: "geometry_msgs", messageName: "Pose")
        #expect(schema.fields[0].type == .nested(schemaName: "geometry_msgs/msg/Point"))
        #expect(schema.fields[1].type == .nested(schemaName: "geometry_msgs/msg/Quaternion"))
    }

    @Test func parsesArrayVariants() throws {
        let text = """
        uint8[] data
        float32[3] vector
        int32[<=10] bounded
        string[] names
        """
        let schema = try parser.parse(text, packageName: "test_msgs", messageName: "Arrays")
        #expect(schema.fields[0].type == .array(.uint8, count: nil))
        #expect(schema.fields[1].type == .array(.float32, count: 3))
        #expect(schema.fields[2].type == .bounded(.int32, maxCount: 10))
        #expect(schema.fields[3].type == .array(.string, count: nil))
    }

    @Test func stripsComments() throws {
        let text = """
        # This is a comment
        float64 x # inline comment
        # another comment
        float64 y
        """
        let schema = try parser.parse(text, packageName: "geometry_msgs", messageName: "Point2")
        #expect(schema.fields.count == 2)
        #expect(schema.fields[0].name == "x")
        #expect(schema.fields[1].name == "y")
    }

    @Test func ignoresBlankLines() throws {
        let text = """

        float64 x

        float64 y

        """
        let schema = try parser.parse(text, packageName: "test", messageName: "T")
        #expect(schema.fields.count == 2)
    }

    @Test func parsesFullQualifiedNestedType() throws {
        let text = "geometry_msgs/msg/Point position"
        let schema = try parser.parse(text, packageName: "nav_msgs", messageName: "Test")
        #expect(schema.fields[0].type == .nested(schemaName: "geometry_msgs/msg/Point"))
    }

    @Test func parsesBuiltinInterfacesType() throws {
        let text = "builtin_interfaces/Time stamp"
        let schema = try parser.parse(text, packageName: "std_msgs", messageName: "Header2")
        #expect(schema.fields[0].type == .nested(schemaName: "builtin_interfaces/msg/Time"))
    }

    @Test func roundTripPointFixture() throws {
        let fixturesURL = Bundle.module.resourceURL!.appendingPathComponent("Fixtures")
        let text = try String(contentsOf: fixturesURL.appendingPathComponent("point_fixture.msg"), encoding: .utf8)
        let schema = try parser.parse(text, packageName: "geometry_msgs", messageName: "Point")
        #expect(schema.fields.count == 3)
        #expect(schema.fields.allSatisfy { $0.type == .float64 })
    }

    @Test func nestedFixtureHasTwoNestedTypes() throws {
        let fixturesURL = Bundle.module.resourceURL!.appendingPathComponent("Fixtures")
        let text = try String(contentsOf: fixturesURL.appendingPathComponent("nested_fixture.msg"), encoding: .utf8)
        let schema = try parser.parse(text, packageName: "test_msgs", messageName: "Nested")
        let nestedCount = schema.fields.filter {
            if case .nested = $0.type { return true }
            return false
        }.count
        #expect(nestedCount == 2)
    }

    @Test func arraysFixtureRoundTrip() throws {
        let fixturesURL = Bundle.module.resourceURL!.appendingPathComponent("Fixtures")
        let text = try String(contentsOf: fixturesURL.appendingPathComponent("arrays_fixture.msg"), encoding: .utf8)
        let schema = try parser.parse(text, packageName: "test_msgs", messageName: "Arrays")
        #expect(schema.fields.count == 4)
    }
}
