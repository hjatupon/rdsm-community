#!/usr/bin/env python3
"""
patch_sdf.py — Injects an Intel RealSense D435-equivalent depth camera sensor
into the installed TurtleBot3 Waffle Pi model.sdf at Docker build time.

Run once from Dockerfile after ros-jazzy-turtlebot3-gazebo is installed:
    python3 /sim-bot/scripts/patch_sdf.py

The patch adds a `camera_depth_link` (with an rgbd_camera sensor) attached to
`camera_rgb_frame` via a fixed joint.  The sensor publishes a full 3D point cloud
on Gazebo topic /rgbd_camera/points (gz.msgs.PointCloudPacked), which is bridged
by the `depth_camera_bridge` ROS-GZ bridge node to /camera/depth/points
(sensor_msgs/msg/PointCloud2).

NOTE ON RENDERING:
  If Gazebo's rgbd_camera sensor fails to produce depth data under ogre1 (Mesa
  llvmpipe software rendering), the entrypoint.sh fallback automatically starts
  scripts/depth_camera_publisher.py instead.  The bridge stays silent in that
  case; the synthetic publisher takes over on /camera/depth/points.
"""

import sys
import shutil
from pathlib import Path

SDF_PATH = Path(
    "/opt/ros/jazzy/share/turtlebot3_gazebo/models/turtlebot3_waffle_pi/model.sdf"
)

# The depth camera sensor block to inject before </model>.
# Attached to camera_rgb_frame (same physical position as the RGB picam).
# Intel RealSense D435 specs:
#   H-FOV 87° = 1.5184 rad, 424×240 depth resolution, 15 Hz, 0.1–5.0 m range.
# Topic /rgbd_camera publishes:
#   /rgbd_camera        (gz.msgs.Image        → RGB — not bridged)
#   /rgbd_camera/depth_image (gz.msgs.Image   → depth — not bridged)
#   /rgbd_camera/points (gz.msgs.PointCloudPacked → /camera/depth/points via bridge)
DEPTH_CAMERA_SDF = """\

    <!-- ── Intel RealSense D435-equivalent depth camera (injected by patch_sdf.py) ── -->
    <!-- Attached to camera_rgb_frame (same location as the Waffle Pi RGB camera).     -->
    <!-- Publishes /rgbd_camera/points (gz.msgs.PointCloudPacked), bridged by          -->
    <!-- depth_camera_bridge to /camera/depth/points (sensor_msgs/PointCloud2).        -->
    <link name="camera_depth_link">
      <pose relative_to="camera_rgb_frame">0 0 0 0 0 0</pose>
      <inertial>
        <mass>0.001</mass>
        <inertia>
          <ixx>1e-9</ixx><ixy>0</ixy><ixz>0</ixz>
          <iyy>1e-9</iyy><iyz>0</iyz><izz>1e-9</izz>
        </inertia>
      </inertial>
      <sensor name="realsense_d435" type="rgbd_camera">
        <always_on>1</always_on>
        <visualize>false</visualize>
        <update_rate>15</update_rate>
        <topic>/rgbd_camera</topic>
        <gz_frame_id>camera_depth_link</gz_frame_id>
        <camera>
          <horizontal_fov>1.5184</horizontal_fov>
          <image>
            <width>424</width>
            <height>240</height>
          </image>
          <clip>
            <near>0.1</near>
            <far>5.0</far>
          </clip>
          <noise>
            <type>gaussian</type>
            <mean>0</mean>
            <stddev>0.005</stddev>
          </noise>
        </camera>
      </sensor>
    </link>

    <joint name="camera_depth_joint" type="fixed">
      <parent>camera_rgb_frame</parent>
      <child>camera_depth_link</child>
    </joint>
    <!-- ── end depth camera ── -->
"""

MARKER = "<!-- depth_camera_patched -->"


def main() -> None:
    if not SDF_PATH.exists():
        print(f"ERROR: {SDF_PATH} not found — is ros-jazzy-turtlebot3-gazebo installed?",
              file=sys.stderr)
        sys.exit(1)

    text = SDF_PATH.read_text()

    if MARKER in text:
        print(f"Already patched — skipping {SDF_PATH}")
        return

    if "</model>" not in text:
        print(f"ERROR: </model> not found in {SDF_PATH}", file=sys.stderr)
        sys.exit(1)

    # Back up original
    backup = SDF_PATH.with_suffix(".sdf.orig")
    if not backup.exists():
        shutil.copy2(SDF_PATH, backup)

    # Inject depth camera block + marker before </model>
    patched = text.replace(
        "  </model>",
        DEPTH_CAMERA_SDF + f"  {MARKER}\n  </model>",
        1,
    )

    SDF_PATH.write_text(patched)
    print(f"Patched: {SDF_PATH}")
    print(f"Backup:  {backup}")


if __name__ == "__main__":
    main()
