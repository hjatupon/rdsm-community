#!/usr/bin/env python3
"""
Synthetic PointCloud2 depth camera publisher — ogre1 fallback for sim-bot.

WHY THIS EXISTS:
  Gazebo Harmonic's rgbd_camera sensor requires depth buffer rendering, which
  may not be available under ogre1 (Mesa llvmpipe) software rendering used in
  headless Docker.  The launch file adds the proper Gazebo rgbd_camera sensor
  to the TurtleBot3 model and bridges /rgbd_camera/points → /camera/depth/points.
  If that Gazebo sensor produces no data after 30 s, entrypoint.sh starts this
  script as a clearly-labeled fallback so /camera/depth/points is always live.

WHAT THIS DOES:
  Subscribes to /scan (sensor_msgs/LaserScan from the 2D LiDAR) and converts
  each scan ray into 16 vertical point layers, producing vertical columns of
  points at obstacle locations.  Publishes as sensor_msgs/PointCloud2 on
  /camera/depth/points at the LaserScan rate (~10–15 Hz).

LIMITATIONS (synthetic, not real depth camera):
  - No real depth rendering; point columns reflect LiDAR obstacle positions only.
  - Floor and ceiling are not sensed (only obstacles in the LiDAR plane).
  - Replace this with a proper Gazebo rgbd_camera if ogre2/GPU rendering is
    ever available in the Docker environment.
"""

import math
import struct

import rclpy
from rclpy.node import Node
from sensor_msgs.msg import LaserScan, PointCloud2, PointField

VERTICAL_LAYERS = 16     # point layers per LiDAR ray
VERTICAL_MIN_M  = -0.15  # lowest layer height relative to base_scan frame (m)
VERTICAL_MAX_M  =  0.65  # highest layer height
MAX_RANGE_M     =  5.0   # clip to realistic RealSense D435 range


class SyntheticDepthCamera(Node):
    def __init__(self) -> None:
        super().__init__('synthetic_depth_camera')
        self.sub = self.create_subscription(LaserScan, '/scan', self._on_scan, 10)
        self.pub = self.create_publisher(PointCloud2, '/camera/depth/points', 10)
        self.get_logger().warn(
            'Synthetic depth camera active (ogre1 fallback — not real depth data). '
            'Point cloud is a LaserScan vertical extrusion. '
            'See scripts/depth_camera_publisher.py for details.'
        )

    def _on_scan(self, scan: LaserScan) -> None:
        heights = [
            VERTICAL_MIN_M + i * (VERTICAL_MAX_M - VERTICAL_MIN_M) / (VERTICAL_LAYERS - 1)
            for i in range(VERTICAL_LAYERS)
        ]

        buf = bytearray()
        count = 0
        angle = scan.angle_min

        for r in scan.ranges:
            if scan.range_min <= r <= min(scan.range_max, MAX_RANGE_M):
                cx = r * math.cos(angle)
                cy = r * math.sin(angle)
                for z in heights:
                    buf += struct.pack('fff', cx, cy, z)
                    count += 1
            angle += scan.angle_increment

        if count == 0:
            return

        fields = [
            PointField(name='x', offset=0,  datatype=PointField.FLOAT32, count=1),
            PointField(name='y', offset=4,  datatype=PointField.FLOAT32, count=1),
            PointField(name='z', offset=8,  datatype=PointField.FLOAT32, count=1),
        ]

        msg = PointCloud2()
        msg.header       = scan.header   # keeps same stamp + frame as the LiDAR
        msg.height       = 1
        msg.width        = count
        msg.fields       = fields
        msg.is_bigendian = False
        msg.point_step   = 12
        msg.row_step     = 12 * count
        msg.data         = bytes(buf)
        msg.is_dense     = True
        self.pub.publish(msg)


def main(args: list | None = None) -> None:
    rclpy.init(args=args)
    node = SyntheticDepthCamera()
    rclpy.spin(node)
    node.destroy_node()
    rclpy.shutdown()


if __name__ == '__main__':
    main()
