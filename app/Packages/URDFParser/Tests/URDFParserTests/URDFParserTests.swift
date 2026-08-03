import Testing
import Foundation
@testable import URDFParser
import RobotModelCore

// MARK: - Helpers

private func fixtureURL(_ name: String) -> URL {
    Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures")!
}

private func parseFixture(_ name: String, baseURL: URL? = nil) throws -> RobotModel {
    let url = fixtureURL(name)
    let xml = try String(contentsOf: url, encoding: .utf8)
    return try URDFParser().parse(xml, baseURL: baseURL ?? url.deletingLastPathComponent())
}

// MARK: - Basic parsing

@Suite("BasicParsing")
struct BasicParsingTests {

    @Test("Minimal URDF: single link, no joints")
    func testMinimal() throws {
        let model = try parseFixture("minimal.urdf")
        #expect(model.links.count == 1)
        #expect(model.links[0].name == "base_link")
        #expect(model.joints.isEmpty)
        #expect(model.rootLink == "base_link")
    }

    @Test("Two-link URDF: parent/child, revolute joint")
    func testTwoLink() throws {
        let model = try parseFixture("two_link.urdf")
        #expect(model.links.count == 2)
        #expect(model.joints.count == 1)
        #expect(model.rootLink == "base_link")
        let joint = model.joints[0]
        #expect(joint.name == "arm_joint")
        #expect(joint.type == .revolute)
        #expect(joint.parent == "base_link")
        #expect(joint.child == "arm")
    }

    @Test("Six-link chain: root detection by child-set exclusion")
    func testChainRobot() throws {
        let model = try parseFixture("chain_robot.urdf")
        #expect(model.links.count == 7)
        #expect(model.joints.count == 6)
        #expect(model.rootLink == "base_link")
    }

    @Test("Mobile base: multiple continuous joints")
    func testMobileBase() throws {
        let model = try parseFixture("mobile_base.urdf")
        #expect(model.links.count == 6)
        let continuous = model.joints.filter { $0.type == .continuous }
        #expect(continuous.count == 2)
        let fixed = model.joints.filter { $0.type == .fixed }
        #expect(fixed.count == 3)
    }
}

// MARK: - Joint types

@Suite("JointTypes")
struct JointTypeTests {

    @Test("All 6 joint types parsed correctly")
    func testAllJointTypes() throws {
        let model = try parseFixture("joint_types.urdf")
        let byName = Dictionary(uniqueKeysWithValues: model.joints.map { ($0.name, $0) })
        #expect(byName["j_revolute"]?.type == .revolute)
        #expect(byName["j_continuous"]?.type == .continuous)
        #expect(byName["j_prismatic"]?.type == .prismatic)
        #expect(byName["j_fixed"]?.type == .fixed)
        #expect(byName["j_floating"]?.type == .floating)
        #expect(byName["j_planar"]?.type == .planar)
    }
}

// MARK: - Origin / axis parsing

@Suite("OriginParsing")
struct OriginParsingTests {

    @Test("Joint origin xyz and rpy parsed into Transform")
    func testOriginXYZ() throws {
        let model = try parseFixture("origin_rpy.urdf")
        #expect(model.joints.count == 1)
        let joint = model.joints[0]
        let t = joint.origin.translation
        #expect(abs(t.x - 1.0) < 1e-5)
        #expect(abs(t.y - 2.0) < 1e-5)
        #expect(abs(t.z - 3.0) < 1e-5)
        // Roll = π/2 → quaternion ix ≈ sin(π/4) ≈ 0.7071
        let ix = joint.origin.rotation.imag.x
        #expect(abs(abs(ix) - 0.7071) < 1e-3)
    }

    @Test("Axis xyz parsed correctly")
    func testAxisParsing() throws {
        let model = try parseFixture("two_link.urdf")
        let joint = model.joints[0]
        #expect(abs(joint.axis.x - 0) < 1e-6)
        #expect(abs(joint.axis.y - 0) < 1e-6)
        #expect(abs(joint.axis.z - 1) < 1e-6)
    }
}

// MARK: - Mesh URL resolution

@Suite("MeshURLResolution")
struct MeshURLResolutionTests {

    @Test("package:// mesh keys retained before resolution")
    func testMeshKeyRetained() throws {
        let model = try parseFixture("mesh_links.urdf")
        let linkWithMesh = model.links.first { $0.meshKey != nil }
        #expect(linkWithMesh != nil)
        #expect(linkWithMesh?.meshKey?.hasPrefix("package://my_robot_description") == true)
    }

    @Test("MeshURLResolver resolves package:// to absolute path")
    func testMeshURLResolver() {
        let fakeRoot = URL(fileURLWithPath: "/opt/ros/my_robot_description")
        let resolver = MeshURLResolver(packagePaths: ["my_robot_description": fakeRoot])
        let resolved = resolver.resolve("package://my_robot_description/meshes/base.dae")
        #expect(resolved?.path == "/opt/ros/my_robot_description/meshes/base.dae")
    }

    @Test("MeshURLResolver returns nil for unknown package")
    func testUnknownPackage() {
        let resolver = MeshURLResolver(packagePaths: [:])
        let result = resolver.resolve("package://unknown_pkg/mesh.dae")
        #expect(result == nil)
    }

    @Test("resolveMeshURLs rewrites links in model")
    func testResolveMeshURLsInModel() throws {
        let model = try parseFixture("mesh_links.urdf")
        let fakeRoot = URL(fileURLWithPath: "/opt/ros/my_robot_description")
        let resolved = URDFParser().resolveMeshURLs(
            model,
            packagePaths: ["my_robot_description": fakeRoot])
        let baseMesh = resolved.links.first { $0.name == "base_link" }?.meshKey
        #expect(baseMesh?.hasPrefix("file:///opt/ros/my_robot_description") == true)
    }
}

// MARK: - Xacro subset

@Suite("XacroSubset")
struct XacroSubsetTests {

    @Test("xacro:property substituted in cylinder geometry")
    func testXacroProperty() throws {
        // The fixture uses ${wheel_radius} and ${wheel_width} in cylinder attributes.
        // After preprocessing those are plain floats; the XML parses without error.
        let model = try parseFixture("xacro_property.urdf.xacro")
        #expect(model.links.count == 3)
        let wheels = model.joints.filter { $0.type == .continuous }
        #expect(wheels.count == 2)
    }

    @Test("xacro:if includes block when truthy, excludes when falsy")
    func testXacroIf() throws {
        let model = try parseFixture("xacro_if.urdf.xacro")
        let linkNames = Set(model.links.map { $0.name })
        // has_arm=1 → arm_link included
        #expect(linkNames.contains("arm_link"))
        // has_gripper=0 → gripper_link excluded
        #expect(!linkNames.contains("gripper_link"))
        // unless(has_gripper) → end_effector_placeholder included
        #expect(linkNames.contains("end_effector_placeholder"))
    }

    @Test("xacro:include inlines child file content")
    func testXacroInclude() throws {
        let model = try parseFixture("xacro_include_parent.urdf.xacro")
        let linkNames = model.links.map { $0.name }
        #expect(linkNames.contains("base_link"))
        #expect(linkNames.contains("sensor_link"))
        #expect(model.joints.contains { $0.name == "sensor_joint" })
    }

    @Test("xacro:macro throws unsupportedXacroFeature")
    func testXacroMacroRejected() {
        let xml = """
        <?xml version="1.0"?>
        <robot name="macro_bot" xmlns:xacro="http://www.ros.org/wiki/xacro">
          <xacro:macro name="make_link" params="name">
            <link name="${name}"/>
          </xacro:macro>
          <xacro:make_link name="foo"/>
        </robot>
        """
        #expect(throws: URDFParserError.self) {
            _ = try URDFParser().parse(xml)
        }
    }
}

// MARK: - Error cases

@Suite("ErrorCases")
struct ErrorCaseTests {

    @Test("Missing robot root element throws missingRootElement")
    func testMissingRoot() {
        let xml = "<?xml version=\"1.0\"?><not_a_robot/>"
        #expect(throws: URDFParserError.self) {
            _ = try URDFParser().parse(xml)
        }
    }

    @Test("Malformed XML throws xmlParseError")
    func testMalformedXML() {
        let xml = "<?xml version=\"1.0\"?><robot name=\"bad\"><link name=\"x\""
        #expect(throws: URDFParserError.self) {
            _ = try URDFParser().parse(xml)
        }
    }

    @Test("xacro:include missing file throws includeFileNotFound")
    func testIncludeFileNotFound() {
        let xml = """
        <?xml version="1.0"?>
        <robot name="broken" xmlns:xacro="http://www.ros.org/wiki/xacro">
          <link name="base_link"/>
          <xacro:include filename="does_not_exist.urdf.xacro"/>
        </robot>
        """
        #expect(throws: URDFParserError.self) {
            _ = try URDFParser().parse(xml, baseURL: URL(fileURLWithPath: "/tmp"))
        }
    }
}
