#!/usr/bin/env python3
"""
Custom launch for TurtleBot3 Waffle Pi + Gazebo + RealSense D435-equivalent depth camera.

The TurtleBot3 model.sdf is patched at Docker build time by scripts/patch_sdf.py
to include an rgbd_camera sensor.  This launch file adds one extra node on top of
the upstream turtlebot3_gazebo launch:

  depth_camera_bridge — ros_gz_bridge that publishes
      /rgbd_camera/points (gz.msgs.PointCloudPacked)
    as
      /camera/depth/points (sensor_msgs/msg/PointCloud2)

If the Gazebo rgbd_camera sensor does not produce depth data under ogre1 software
rendering, entrypoint.sh step 4b detects the silence after 30 s and starts
scripts/depth_camera_publisher.py as a documented synthetic fallback.
"""

import os

from ament_index_python.packages import get_package_share_directory
from launch import LaunchDescription
from launch.actions import AppendEnvironmentVariable, IncludeLaunchDescription
from launch.launch_description_sources import PythonLaunchDescriptionSource
from launch.substitutions import LaunchConfiguration
from launch_ros.actions import Node


def generate_launch_description():
    launch_file_dir = os.path.join(
        get_package_share_directory('turtlebot3_gazebo'), 'launch')
    ros_gz_sim = get_package_share_directory('ros_gz_sim')

    use_sim_time = LaunchConfiguration('use_sim_time', default='true')
    x_pose = LaunchConfiguration('x_pose', default='-2.0')
    y_pose = LaunchConfiguration('y_pose', default='-0.5')

    # Use our patched world: render_engine=ogre (Mesa-compatible) + inline Ground Plane/Sun
    # so there is no runtime Fuel network dependency and camera sensors work headless.
    world = '/sim-bot/worlds/turtlebot3_world_headless.world'

    gzserver_cmd = IncludeLaunchDescription(
        PythonLaunchDescriptionSource(
            os.path.join(ros_gz_sim, 'launch', 'gz_sim.launch.py')
        ),
        launch_arguments={
            'gz_args': [
                '-r -s --headless-rendering -v2 ',
                world
            ],
            'on_exit_shutdown': 'true'
        }.items()
    )

    # Spawns the patched model.sdf (contains rgbd_camera sensor after patch_sdf.py runs)
    # and sets up the standard bridges (scan, TF, camera/image_raw, clock, odom, imu).
    spawn_cmd = IncludeLaunchDescription(
        PythonLaunchDescriptionSource(
            os.path.join(launch_file_dir, 'spawn_turtlebot3.launch.py')
        ),
        launch_arguments={
            'x_pose': x_pose,
            'y_pose': y_pose
        }.items()
    )

    robot_state_cmd = IncludeLaunchDescription(
        PythonLaunchDescriptionSource(
            os.path.join(launch_file_dir, 'robot_state_publisher.launch.py')
        ),
        launch_arguments={'use_sim_time': use_sim_time}.items()
    )

    # Bridge Gazebo rgbd_camera point cloud → /camera/depth/points.
    # '[' = Gazebo → ROS.  Remapped from /rgbd_camera/points → /camera/depth/points.
    # If the sensor produces no data under ogre1, entrypoint.sh starts the synthetic
    # fallback (scripts/depth_camera_publisher.py) after a 30-second timeout.
    depth_bridge_cmd = Node(
        package='ros_gz_bridge',
        executable='parameter_bridge',
        arguments=[
            '/rgbd_camera/points@sensor_msgs/msg/PointCloud2[gz.msgs.PointCloudPacked',
        ],
        remappings=[('/rgbd_camera/points', '/camera/depth/points')],
        output='screen',
        name='depth_camera_bridge',
    )

    set_env_vars_resources = AppendEnvironmentVariable(
        'GZ_SIM_RESOURCE_PATH',
        os.path.join(
            get_package_share_directory('turtlebot3_gazebo'),
            'models'
        )
    )

    ld = LaunchDescription()
    ld.add_action(set_env_vars_resources)
    ld.add_action(gzserver_cmd)
    ld.add_action(spawn_cmd)
    ld.add_action(robot_state_cmd)
    ld.add_action(depth_bridge_cmd)
    return ld
