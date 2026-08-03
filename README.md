# RDSM Community

**Robotics Developer Studio for Mac** — the free, open-source core.

**Website:** https://hjatupon.github.io/rdsm-community/

A native macOS cockpit for ROS 2 developers. The Mac is the beautiful cockpit; the
Linux robot is the engine. Built with SwiftUI + Metal, talking to robots over
rosbridge (WebSocket) — no ROS installation required on your Mac.

> **RDSM Community** is the open-source foundation. **RDSM Pro** adds advanced
> debugging tools (rosbag record/replay, time-series plotting, parameter profiles,
> purpose-built inspector visualizations, the immersive TF Universe, message
> templates, and more) and is available on the Mac App Store.

## Features (Community)

- **3D Visualizer** — 14 layer types (LaserScan, PointCloud2, OccupancyGrid, Octomap,
  Image, Odometry, MarkerArray, Path, TF frames, RobotModel, maps, …) on a Metal 4 renderer
- **Topic Browser & Inspector** — raw/JSON message inspection
- **Basic TF Tree** — text + diagram view
- **Log Viewer** — /rosout with severity filters and search
- **Robot Model** — URDF loading with `package://` mesh resolution
- **Message Publishing** — String / Twist / TwistStamped / Raw JSON
- **Nav2 Goal & 2D Pose Estimate** tools (click-drag on the 3D floor)
- **Service Call UI** — browse and call ROS 2 services

## Requirements

- macOS 15 (Sequoia) or later
- [XcodeGen](https://github.com/yonoson/XcodeGen) (`brew install xcodegen`)
- Xcode 16+

## Build & run

```bash
cd app
xcodegen generate --spec project.yml
xcodebuild -project ROS2Studio.xcodeproj -scheme ROS2Studio build
open "$(find ~/Library/Developer/Xcode/DerivedData -name 'ROS2Studio.app' -path '*/Debug/*' | head -1)"
```

## Try it against a simulated robot

A Docker sim-bot (TurtleBot3 + Nav2 + rosbridge) is included:

```bash
cd testing/sim-bot
docker compose up -d
# then connect the app to ws://localhost:9090
```

## Architecture

The app is a set of SwiftPM packages composed by a thin app target. See
[`CLAUDE.md`](CLAUDE.md) for the package map and technical conventions.

## Contributing

Contributions are welcome — see [`CONTRIBUTING.md`](CONTRIBUTING.md).

## License

Apache License 2.0 — see [`LICENSE`](LICENSE).
