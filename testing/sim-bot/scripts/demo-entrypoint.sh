#!/bin/bash
# demo-entrypoint.sh — plays the pre-recorded demo MCAP through rosbridge_suite.
# Launched by docker compose --profile demo up
# No Gazebo, no display needed — lightweight playback-only container.
set -euo pipefail

MCAP_DIR="/sim-bot/demo-recording"

echo "==> [1/3] Sourcing ROS 2 Jazzy"
# shellcheck disable=SC1091
set +u; source /opt/ros/jazzy/setup.bash; set -u

export ROS_DOMAIN_ID=0

# ── Verify the demo recording exists ─────────────────────────────────────────
if [ ! -d "$MCAP_DIR" ]; then
    echo ""
    echo "ERROR: Demo recording not found at $MCAP_DIR"
    echo ""
    echo "  Run the following to record a fresh demo:"
    echo "    cd testing/sim-bot"
    echo "    make record-demo   (or: ./scripts/record-demo.sh)"
    echo ""
    exit 1
fi

# ── Start rosbridge_server ────────────────────────────────────────────────────
echo "==> [2/3] Starting rosbridge_server on port 9090"
ros2 launch rosbridge_server rosbridge_websocket_launch.xml \
    port:=9090 \
    address:=0.0.0.0 \
    ssl:=false \
    unregister_timeout:=10.0 &
BRIDGE_PID=$!

sleep 3
echo "       rosbridge_server ready on ws://0.0.0.0:9090"

# ── Play the MCAP in a loop ───────────────────────────────────────────────────
echo "==> [3/3] Playing demo recording in loop"
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  ROS2 Studio Demo — Sim-bot Playback                        ║"
echo "║  rosbridge_server: ws://0.0.0.0:9090                        ║"
echo "║                                                              ║"
echo "║  In ROS2 Studio: click 'Try Demo' to connect                ║"
echo "║                                                              ║"
echo "║  Topics:                                                     ║"
echo "║    /scan              LaserScan   (2D LiDAR)                 ║"
echo "║    /camera/image_raw/compressed   (RGB camera, JPEG)        ║"
echo "║    /odom              Odometry    (wheel odometry)           ║"
echo "║    /imu               Imu         (inertial)                 ║"
echo "║    /map               OccupancyGrid (SLAM map)               ║"
echo "║    /tf + /tf_static   TransformTree                          ║"
echo "║    /joint_states      JointState                             ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

while true; do
    echo "[demo] Starting bag playback…"
    ros2 bag play "$MCAP_DIR" --clock || true
    echo "[demo] Bag finished — restarting loop in 2s"
    sleep 2
done
