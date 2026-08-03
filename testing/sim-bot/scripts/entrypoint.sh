#!/bin/bash
# entrypoint.sh — starts TurtleBot3 Gazebo + SLAM + random walker + rosbridge_server.
#
# Self-healing design: all processes run in the background; a monitor loop
# exits the container with code 1 if Gazebo or rosbridge die so that
# Docker's "restart: unless-stopped" policy relaunches everything cleanly.
set -euo pipefail

# ── 1. Virtual display ────────────────────────────────────────────────────────
echo "==> [1/5] Starting Xvfb :99"
# Remove stale lock files left by a previous container run so Xvfb can start
# on restart without "Server is already active for display 99" errors.
rm -f /tmp/.X99-lock /tmp/.X11-unix/X99
Xvfb :99 -screen 0 1280x720x24 -nolisten tcp &
XVFB_PID=$!
sleep 1

# ── 2. Source ROS 2 ───────────────────────────────────────────────────────────
echo "==> [2/5] Sourcing ROS 2 Jazzy"
# shellcheck disable=SC1091
set +u; source /opt/ros/jazzy/setup.bash; set -u

export TURTLEBOT3_MODEL=waffle_pi
export ROS_DOMAIN_ID=0

# ── Rendering: ogre (ogre1) + Mesa llvmpipe software rendering ───────────────
# ogre2 requires a real GPU; ogre (ogre1) works with Mesa llvmpipe in headless
# Docker. The render_engine is set to "ogre" in worlds/turtlebot3_world_headless.world
# so the camera sensor produces real images without a physical GPU.
export LIBGL_ALWAYS_SOFTWARE=1
export MESA_GL_VERSION_OVERRIDE=3.3
export GALLIUM_DRIVER=llvmpipe
export DISPLAY=:99

# ── 3. Launch TurtleBot3 Gazebo simulation ────────────────────────────────────
# The custom launch uses our patched world (ogre renderer, no Fuel dependency)
# and includes ros_gz_bridge + ros_gz_image via spawn_turtlebot3.launch.py.
echo "==> [3/5] Launching TurtleBot3 Gazebo (headless ogre1, camera + scan + TF)"
ros2 launch /sim-bot/launch/turtlebot3_camera.launch.py &
SIM_PID=$!

# ── 4. Wait for simulation to be ready ────────────────────────────────────────
echo "==> [4/5] Waiting for /scan to start…"
TIMEOUT=180
ELAPSED=0
until ros2 topic list 2>/dev/null | grep -q "^/scan$" || [ $ELAPSED -ge $TIMEOUT ]; do
    sleep 3
    ELAPSED=$((ELAPSED + 3))
    echo "       …waiting ($ELAPSED / ${TIMEOUT}s)"
done

if [ $ELAPSED -ge $TIMEOUT ]; then
    echo "ERROR: /scan not detected after ${TIMEOUT}s — Gazebo may have failed. Exiting."
    exit 1
fi
echo "       /scan detected — Gazebo + LiDAR bridge running"

# Wait for camera image bridge to initialise (ogre1 renderer takes a few seconds)
echo "       Waiting for camera image bridge…"
CAM_WAIT=0
until ros2 topic list 2>/dev/null | grep -q "^/camera/image_raw$" || [ $CAM_WAIT -ge 30 ]; do
    sleep 2
    CAM_WAIT=$((CAM_WAIT + 2))
done
if ros2 topic list 2>/dev/null | grep -q "^/camera/image_raw$"; then
    echo "       /camera/image_raw detected — camera is live"
else
    echo "WARNING: /camera/image_raw not detected after 30s — camera may still be initialising"
fi

# ── 4b. Check for depth point cloud (Gazebo rgbd_camera or synthetic fallback) ─
# The launch file adds an rgbd_camera sensor to the TurtleBot3 model and bridges
# /rgbd_camera/points → /camera/depth/points via ros_gz_bridge.
# If the Gazebo depth sensor doesn't produce data under ogre1 (Mesa llvmpipe),
# we start scripts/depth_camera_publisher.py as a synthetic fallback.
echo "       Waiting up to 30s for /camera/depth/points (Gazebo rgbd_camera)…"
# Try up to 10 times (3s timeout per attempt) = 30s max.
# ros2 topic echo --once exits after one message; timeout 3 prevents hanging
# when the Gazebo depth sensor produces no data under ogre1 rendering.
DEPTH_OK=0
for _try in 1 2 3 4 5 6 7 8 9 10; do
    if timeout 3 ros2 topic echo /camera/depth/points --once 2>/dev/null | grep -q "is_dense"; then
        DEPTH_OK=1
        break
    fi
done

if [ $DEPTH_OK -eq 1 ]; then
    echo "       /camera/depth/points live — Gazebo rgbd_camera depth sensor working"
else
    echo "       /camera/depth/points empty — ogre1 may not support rgbd_camera depth rendering"
    echo "       Starting synthetic depth camera (LaserScan vertical extrusion fallback)…"
    python3 /sim-bot/scripts/depth_camera_publisher.py &
    DEPTH_PID=$!
    sleep 3
    if ros2 topic list 2>/dev/null | grep -q "^/camera/depth/points$"; then
        echo "       /camera/depth/points now live via synthetic publisher"
    else
        echo "WARNING: /camera/depth/points still not available — check depth_camera_publisher.py"
    fi
fi

# ── 4c. Launch SLAM toolbox ───────────────────────────────────────────────────
echo "       Starting slam_toolbox (online async)..."
ros2 launch slam_toolbox online_async_launch.py \
    use_sim_time:=True \
    &
SLAM_PID=$!
sleep 3

# ── 4d. Launch Nav2 navigation ────────────────────────────────────────────────
# Uses navigation_launch.py (no AMCL) — SLAM Toolbox provides the map→odom→base TF.
# enable_stamped_cmd_vel=true in nav2_params.yaml ensures the whole velocity chain
# publishes geometry_msgs/msg/TwistStamped, matching the ros_gz_bridge expectation.
echo "       Starting Nav2 navigation stack (bt_navigator + planner + controller)..."
ros2 launch /sim-bot/launch/nav2_navigation.launch.py \
    use_sim_time:=True \
    params_file:=/sim-bot/config/nav2_params.yaml \
    &
NAV2_PID=$!
sleep 8
echo "       Nav2 ready — publish PoseStamped to /goal_pose to navigate the robot"

# ── 4e. Publish /robot_description ────────────────────────────────────────────
echo "       Publishing TurtleBot3 URDF to /robot_description…"
python3 /sim-bot/scripts/publish_robot_description.py &
ROBOT_DESC_PID=$!
sleep 2
echo "       /robot_description published"

# ── 4f. ros2_studio_recorder node ──────────────────────────────────────────────
echo "       Starting ros2_studio_recorder (remote bag recording service)..."
# -u disables Python output buffering so errors appear immediately in docker logs.
python3 -u /sim-bot/ros2_studio_recorder/recorder_node.py &
RECORDER_PID=$!
sleep 2
if kill -0 "$RECORDER_PID" 2>/dev/null; then
    echo "       ros2_studio_recorder process running (PID $RECORDER_PID)"
else
    echo "WARNING: ros2_studio_recorder process exited — check python path and imports"
fi
# Wait up to 10s for set_parameters service to appear
SVC_WAIT=0
until ros2 service list 2>/dev/null | grep -q "/ros2_studio/recorder/start" || [ $SVC_WAIT -ge 10 ]; do
    sleep 1
    SVC_WAIT=$((SVC_WAIT + 1))
done
if ros2 service list 2>/dev/null | grep -q "/ros2_studio/recorder/start"; then
    echo "       /ros2_studio/recorder/{start,stop,status} services ready"
else
    echo "WARNING: recorder services not detected after ${SVC_WAIT}s"
fi

# ── 5. Random velocity walker (disabled — start manually if you want map coverage)
# To enable: docker exec sim-bot-sim-1 python3 /sim-bot/scripts/nav_goals.py &
echo "==> [5/5] Random walker disabled (start manually to drive robot)"
NAV_PID=""

# ── rosbridge_server (background) ────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  rosbridge_server listening on ws://0.0.0.0:9090            ║"
echo "║  In ROS2 Studio: Connect → ws://localhost:9090              ║"
echo "║                                                              ║"
echo "║  Topics published:                                           ║"
echo "║    /scan              sensor_msgs/LaserScan   (2D LiDAR)    ║"
echo "║    /camera/image_raw  sensor_msgs/Image        (RGB camera)  ║"
echo "║    /camera/depth/points sensor_msgs/PointCloud2 (depth cam) ║"
echo "║    /map               nav_msgs/OccupancyGrid  (SLAM)         ║"
echo "║    /goal_pose         geometry_msgs/PoseStamped (Nav2 goal)  ║"
echo "║    /plan              nav_msgs/Path            (Nav2 path)   ║"
echo "║    /robot_description std_msgs/String         (URDF model)   ║"
echo "║  Services:                                                    ║"
echo "║    /ros2_studio/recorder/start   Trigger   (remote bag rec)   ║"
echo "║    /ros2_studio/recorder/stop    Trigger   (stop recording)   ║"
echo "║    /ros2_studio/recorder/status  Trigger   (poll status)      ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

ros2 launch rosbridge_server rosbridge_websocket_launch.xml \
    port:=9090 \
    address:=0.0.0.0 \
    ssl:=false \
    unregister_timeout:=10.0 \
    rosapi:=true &
BRIDGE_PID=$!

# ── Process monitor ───────────────────────────────────────────────────────────
# If Gazebo or rosbridge die, exit the container so Docker's restart policy
# (restart: unless-stopped) relaunches the whole simulation cleanly.
echo "All services started. Monitoring critical processes…"
while true; do
    sleep 10
    if ! kill -0 "$SIM_PID" 2>/dev/null; then
        echo "ERROR: Gazebo process (PID $SIM_PID) died. Exiting for Docker restart."
        exit 1
    fi
    if ! kill -0 "$BRIDGE_PID" 2>/dev/null; then
        echo "ERROR: rosbridge process (PID $BRIDGE_PID) died. Exiting for Docker restart."
        exit 1
    fi
    if [ -n "$RECORDER_PID" ] && ! kill -0 "$RECORDER_PID" 2>/dev/null; then
        echo "WARNING: ros2_studio_recorder (PID $RECORDER_PID) died — restarting..."
        python3 -u /sim-bot/ros2_studio_recorder/recorder_node.py &
        RECORDER_PID=$!
        sleep 2
        if kill -0 "$RECORDER_PID" 2>/dev/null; then
            echo "       ros2_studio_recorder restarted (PID $RECORDER_PID)"
        else
            echo "ERROR: ros2_studio_recorder restart failed — recording disabled for this session."
            RECORDER_PID=""
        fi
    fi
done
