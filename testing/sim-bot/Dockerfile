FROM osrf/ros:jazzy-desktop

ENV DEBIAN_FRONTEND=noninteractive
ENV TURTLEBOT3_MODEL=waffle_pi
ENV ROS_DOMAIN_ID=0

# Software rendering — required for Gazebo in headless Docker (no GPU passthrough on Mac)
# ogre1 renderer is used (--render-engine-server ogre) because ogre2 needs a real GPU.
# Mesa 25.x llvmpipe supports ogre1 rendering including the camera sensor plugin.
ENV LIBGL_ALWAYS_SOFTWARE=1
ENV MESA_GL_VERSION_OVERRIDE=3.3
ENV GALLIUM_DRIVER=llvmpipe
ENV DISPLAY=:99

# ── Gazebo Harmonic apt repo ────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
        curl ca-certificates lsb-release \
    && curl https://packages.osrfoundation.org/gazebo.gpg \
       --output /usr/share/keyrings/pkgs-osrf-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) \
       signed-by=/usr/share/keyrings/pkgs-osrf-archive-keyring.gpg] \
       http://packages.osrfoundation.org/gazebo/ubuntu-stable \
       $(lsb_release -cs) main" \
       > /etc/apt/sources.list.d/gazebo-stable.list \
    && rm -rf /var/lib/apt/lists/*

# ── Main packages ────────────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Virtual display for Gazebo's renderer
    xvfb \
    libgl1-mesa-dri \
    libgles2 \
    # Gazebo Harmonic
    gz-harmonic \
    # ROS 2 ↔ Gazebo bridge (topics, TF, clock, camera, LIDAR, joints)
    ros-jazzy-ros-gz \
    # TurtleBot3
    ros-jazzy-turtlebot3 \
    ros-jazzy-turtlebot3-msgs \
    ros-jazzy-turtlebot3-gazebo \
    # Navigation2
    ros-jazzy-nav2-bringup \
    ros-jazzy-navigation2 \
    ros-jazzy-slam-toolbox \
    ros-jazzy-nav2-simple-commander \
    # rosbridge_suite — WebSocket JSON bridge for Mac app
    ros-jazzy-rosbridge-suite \
    # ros2_studio_recorder — Python deps for bag parsing
    python3-yaml \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /sim-bot
COPY . /sim-bot/
# ros2_studio_recorder is mounted via docker-compose volume (../ros2_studio_recorder)
# to allow live edits without rebuilding. The directory is created at runtime.
RUN mkdir -p /sim-bot/ros2_studio_recorder

RUN chmod +x /sim-bot/scripts/entrypoint.sh \
             /sim-bot/scripts/nav_goals.py \
             /sim-bot/scripts/depth_camera_publisher.py \
             /sim-bot/scripts/publish_robot_description.py \
    && chmod +x /sim-bot/launch/turtlebot3_camera.launch.py 2>/dev/null || true

# Patch the TurtleBot3 Waffle Pi model.sdf to add a RealSense D435-equivalent
# rgbd_camera sensor.  The spawn_turtlebot3.launch.py reads model.sdf directly
# (not robot_description), so this is the only way to add the depth camera to
# the Gazebo simulation without forking the upstream package.
RUN python3 /sim-bot/scripts/patch_sdf.py

EXPOSE 9090

ENTRYPOINT ["/sim-bot/scripts/entrypoint.sh"]
