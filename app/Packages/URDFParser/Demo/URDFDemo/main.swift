import URDFParser
import Foundation

// Demo: parse a minimal inline URDF and print the robot model summary.

let urdf = """
<?xml version="1.0"?>
<robot name="demo_bot">
  <link name="base_link"/>
  <link name="arm_link">
    <visual>
      <geometry>
        <mesh filename="package://demo_robot/meshes/arm.dae"/>
      </geometry>
    </visual>
  </link>
  <joint name="arm_joint" type="revolute">
    <parent link="base_link"/>
    <child link="arm_link"/>
    <origin xyz="0.1 0 0.5" rpy="0 0 0"/>
    <axis xyz="0 0 1"/>
  </joint>
</robot>
"""

do {
    let parser = URDFParser()
    let model = try parser.parse(urdf)

    print("Robot parsed successfully")
    print("Root link: \(model.rootLink)")
    print("Links (\(model.links.count)):")
    for link in model.links {
        let mesh = link.meshKey ?? "(none)"
        print("  \(link.name) — mesh: \(mesh)")
    }
    print("Joints (\(model.joints.count)):")
    for joint in model.joints {
        print("  \(joint.name): \(joint.parent) → \(joint.child) [\(joint.type)]")
    }
} catch {
    print("Error: \(error)")
    exit(1)
}
