#!/bin/bash
# record-demo.sh — records a fresh 3-minute demo MCAP from the running sim-bot.
#
# Prerequisites:
#   docker compose up -d   (full sim-bot must be running)
#
# Output: testing/sim-bot/demo-recording/ (mounted into demo service as read-only volume)
#
# Usage:
#   cd testing/sim-bot
#   ./scripts/record-demo.sh
set -euo pipefail

CONTAINER="sim-bot-sim-1"
DURATION=185   # 3 min + 5s buffer
OUTPUT_DIR_CONTAINER="/tmp/demo-recording"
OUTPUT_DIR_HOST="$(dirname "$0")/../demo-recording"

echo "==> Checking sim-bot container is running…"
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
    echo "ERROR: Container '$CONTAINER' is not running."
    echo "  Start it first: cd testing/sim-bot && docker compose up -d"
    exit 1
fi

echo "==> Cleaning up any previous recording in container…"
docker exec "$CONTAINER" bash -c "rm -rf $OUTPUT_DIR_CONTAINER" 2>/dev/null || true

echo "==> Commanding robot to move in a circle…"
docker exec -d "$CONTAINER" bash -c "
    source /opt/ros/jazzy/setup.bash
    export ROS_DOMAIN_ID=0
    ros2 topic pub -r 10 /cmd_vel geometry_msgs/msg/Twist \
      '{linear: {x: 0.15, y: 0.0, z: 0.0}, angular: {x: 0.0, y: 0.0, z: 0.3}}' &
    sleep $((DURATION + 5))
    kill %1 2>/dev/null || true
" 2>/dev/null &

echo "==> Recording ${DURATION}s of sim-bot data (3-minute demo)…"
echo "     Topics: /scan, /camera/image_raw/compressed, /odom, /imu,"
echo "             /tf, /tf_static, /map, /joint_states, /robot_description, /pose, /rosout"

docker exec "$CONTAINER" bash -c "
    source /opt/ros/jazzy/setup.bash
    export ROS_DOMAIN_ID=0
    timeout $DURATION ros2 bag record \
      -o $OUTPUT_DIR_CONTAINER \
      /scan /camera/image_raw/compressed /odom /imu \
      /tf /tf_static /map /joint_states /robot_description /pose /rosout
    echo 'Recording complete.'
"

echo "==> Copying recording from container to host…"
rm -rf "$OUTPUT_DIR_HOST"
docker cp "${CONTAINER}:${OUTPUT_DIR_CONTAINER}" "$OUTPUT_DIR_HOST"

echo ""
echo "✅ Demo recording saved to: $OUTPUT_DIR_HOST"
echo "   Size: $(du -sh "$OUTPUT_DIR_HOST" | cut -f1)"
echo ""
echo "Start the demo service:"
echo "   docker compose --profile demo up"
