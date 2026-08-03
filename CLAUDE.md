# RDSM Community — Architecture & Technical Guide

Native macOS cockpit for ROS 2. SwiftUI + Metal 4, talking to robots over rosbridge
(WebSocket). This repository is the open-source **core**; the shell is shared as a
SwiftPM package (`AppShell`) so the paid edition can consume it directly.

---

## Doctrine (technical)

- **Native Mac only.** SwiftUI + Metal 4. No Electron, webviews, or cross-platform
  abstractions.
- **Cockpit, not engine.** The Mac observes/visualizes/commands over rosbridge. It never
  runs ROS nodes and never talks to hardware.
- **No IDE / no code editing.** This is a visualization & debugging cockpit.
- **Coordinate system is LOCKED.** `Metal(x,y,z) = (-ROS_y, ROS_z, ROS_x)`; quaternion
  `(-ROS_qy, ROS_qz, ROS_qx, ROS_qw)`. Nav goal reverse-swizzle: `ROS(x,y) = (hitZ, -hitX)`.
- **No unit tests.** Manual/visual verification against real robots and the Docker sim-bot.
- **Swift 6 strict concurrency.** All shared state behind actors or `@MainActor`.

## Build & run

```bash
cd app
xcodegen generate --spec project.yml
xcodebuild -project ROS2Studio.xcodeproj -scheme ROS2Studio build
open "$(find ~/Library/Developer/Xcode/DerivedData -name 'ROS2Studio.app' -path '*/Debug/*' | head -1)"
```

Min macOS 15. Xcode 16+. `brew install xcodegen`.

## Testing environment

`testing/sim-bot` — Docker (TurtleBot3 + Nav2 + rosbridge). `docker compose up -d`, then
connect to `ws://localhost:9090`.

## Architecture

- **SwiftPM packages** under `app/Packages/`, each owning one capability. Composed by a
  thin app target (`app/ROS2Studio/`, `@main` → `AppShell.AppRootScene`).
- **`AppShell`** — the shared application shell: composition root (`AppServices`), main
  window, settings, onboarding, performance, and the plugin-registry seams
  (`ProUIRegistry`, `SessionLifecycleObserver`). Paid features are injected at launch via
  these seams; the Community build registers none, so they're absent by construction.
- **Rendering** — `MetalCore` (shared context), `PointCloudRenderer`, `RobotModelRenderer`,
  `Viewer3DUI` (the 3D viewport + layer system + 14 layer types).
- **Data** — `Transport` (rosbridge v2 WebSocket), `TopicStore` (subscription fan-out +
  ring buffer), `MessageRegistry`, `Serialization`, `TFTree`, `LogStore`.
- **UI** — `ConnectionUI`, `TopicBrowserUI`, `InspectorUI` (raw/JSON inspection +
  injectable `VisualizationRegistry`), `LogViewerUI`, `PublishUI`, `ServiceCallUI`.
- **Robot model** — `RobotModelLoader` (`package://` 3-step resolution), `URDFParser`,
  `MeshLoader`, `RobotModelCore`.

### Plugin seams (open-core)

The shell references advanced features only through abstractions, so the paid edition can
inject them without the shell depending on any paid package:

- `ProUIRegistry` (in `AppShell`) — right-panel tabs, publish sheet, replay bar, bag
  manager, recording toolbar, session-lifecycle observers.
- `VisualizationRegistry` (in `InspectorUI`) — inspector visualizations + the viz-picker
  bar. The Community build ships the raw JSON tree only.
- `ViewportModeRegistry` (in `Viewer3DUI`) — alternate 3D viewport modes (e.g. an
  immersive TF visualization). The Community build ships the Scene view + basic TF tree.

## Per-package notes

Each package has its own `CLAUDE.md` with module-specific conventions (wire protocol,
render order, coordinate swizzle, subscription lifecycle, etc.). Read the nearest one when
working inside a package.
