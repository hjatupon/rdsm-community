#!/usr/bin/env python3
"""
Random walker — publishes cmd_vel to drive TurtleBot3 around the world.
No Nav2 dependency. Alternates between driving forward and turning so the
robot explores the map and slam_toolbox builds up coverage.
"""

import random
import rclpy
from rclpy.node import Node
from geometry_msgs.msg import TwistStamped


class RandomWalker(Node):
    def __init__(self):
        super().__init__('random_walker')
        # ros_gz_bridge expects TwistStamped on /cmd_vel (turtlebot3_waffle_pi_bridge.yaml)
        self.pub = self.create_publisher(TwistStamped, '/cmd_vel', 10)
        self.timer = self.create_timer(0.1, self.tick)
        self.phase = 'forward'
        self.phase_ticks = 0
        self.phase_max = 30   # ticks per phase (0.1s each → 3s forward initially)
        self.turn_dir = 1.0
        self.get_logger().info('Random walker started')

    def tick(self):
        msg = TwistStamped()
        msg.header.stamp = self.get_clock().now().to_msg()
        if self.phase == 'forward':
            msg.twist.linear.x = 0.2
            msg.twist.angular.z = 0.0
        else:
            msg.twist.linear.x = 0.0
            msg.twist.angular.z = self.turn_dir * random.uniform(0.5, 1.0)

        self.pub.publish(msg)
        self.phase_ticks += 1

        if self.phase_ticks >= self.phase_max:
            self.phase_ticks = 0
            if self.phase == 'forward':
                self.phase = 'turn'
                self.phase_max = random.randint(10, 25)
                self.turn_dir = random.choice([-1.0, 1.0])
            else:
                self.phase = 'forward'
                self.phase_max = random.randint(20, 50)


def main():
    rclpy.init()
    node = RandomWalker()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == '__main__':
    main()
