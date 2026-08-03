#!/usr/bin/env python3
"""Read the TurtleBot3 URDF, strip xacro syntax, and publish to /robot_description."""

import re
import sys
import rclpy
from std_msgs.msg import String

URDF_PATH = '/opt/ros/jazzy/share/turtlebot3_description/urdf/turtlebot3_waffle_pi.urdf'

robot_desc = open(URDF_PATH).read()
robot_desc = re.sub(r'<xacro:arg[^>]*/>', '', robot_desc)
robot_desc = re.sub(r'<xacro:property[^>]*/>', '', robot_desc)
robot_desc = robot_desc.replace('${namespace}', '')
robot_desc = re.sub(r'^\s*<!--.*?-->\s*$', '', robot_desc, flags=re.MULTILINE)
robot_desc = re.sub(r'\n{3,}', '\n\n', robot_desc)

rclpy.init()
node = rclpy.create_node('robot_description_publisher')
pub = node.create_publisher(String, '/robot_description', 1)

msg = String()
msg.data = robot_desc

pub.publish(msg)
node.get_logger().info(f'Published /robot_description ({len(robot_desc)} chars)')

rclpy.shutdown()
