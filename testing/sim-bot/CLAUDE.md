# sim-bot — ROS2 Simulation Environment

## Quick Start (after every reboot)
```bash
cd ~/Desktop/ros-studio/testing/sim-bot
docker compose up -d                    # start (~90s boot)
docker compose logs -f                  # watch; ready when you see:
                                        # "rosbridge_websocket: Rosbridge WebSocket server started on port 9090"
```

Connect ROS2 Studio to `ws://localhost:9090`

To stop: `docker compose down`

## Stack
- TurtleBot3 Waffle Pi + Gazebo Harmonic + SLAM Toolbox
- Nav2 (custom launch, no collision_monitor — SIGABRT on Jazzy)
- Random walker (nav_goals.py, TwistStamped output)
- rosbridge_suite on port 9090

## Key Topics
/scan, /odom, /imu, /tf, /tf_static, /map, /joint_states, /camera/image_raw, /camera/depth/points, /cmd_vel (TwistStamped), /rosout, /goal_pose

## Nav2
- cmd_vel type: geometry_msgs/msg/TwistStamped (required by ros_gz_bridge for Jazzy)
- enable_stamped_cmd_vel: true in controller_server + velocity_smoother
- Goal topic: /goal_pose (PoseStamped, frame_id: "map")

## Recorder HTTP Server (port 9091)
- `recorder_node.py` is volume-mounted (live edits, no rebuild needed)
- `ros2 bag record -o <path>` creates a **directory** at `<path>/` containing `metadata.yaml` and `<basename>_0.mcap` (the actual data)
- `/list` walks BAGS_DIR, uses `glob("*.mcap")` inside each bag directory to find the data file
- `/download/<name>` detects if `<name>` is a directory, resolves to `*.mcap` child, streams it with `Content-Length` so URLSession reports real progress
- After editing recorder_node.py: `rm -rf testing/ros2_studio_recorder/__pycache__/` then `pkill -f recorder_node.py` inside the container (monitor loop restarts it)
- Verify: `docker exec sim-bot-sim-1 curl -s http://localhost:9091/list`

## Gotchas
- collision_monitor crashes with SIGABRT on Jazzy nav2_bringup — removed from launch
- Random walker overrides single-shot publishes — robot moves despite PublishView commands
- Nav Goal auto-switches fixed frame to "map"
- `add_on_shutdown_hook` does not exist on `rclpy.Node` in Jazzy — fixed in recorder_node.py (use try/finally in main instead)
- On container restart, `/tmp/.X99-lock` from the previous run blocks Xvfb → Gazebo crashes — fixed in entrypoint.sh (rm lock before Xvfb start)
- Monitor loop now restarts the recorder process on crash instead of killing the whole container
- Stale `__pycache__` in Docker volume mount can mask fixes to recorder_node.py — always delete before testing edits
