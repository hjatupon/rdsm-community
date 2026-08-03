# Viewer3DUI — 3D Viewer Feature

## Key Files
- `Viewer3DViewModel.swift` (1863 lines) — central VM, all 10+ message handlers, layer lifecycle
- `Viewer3DView.swift` (862 lines) — SwiftUI composition: layers sidebar + Metal canvas + camera toolbar
- `LayersPanel.swift` (1818 lines) — layer list, add/remove/reorder, settings popovers
- `CameraState.swift` (100 lines) — pure-value orbit camera (azimuth/elevation/distance/target)
- `CameraToolbar.swift` (130 lines) — 6 camera modes + fixed frame picker
- `PointCloudMetalView.swift` (331 lines) — NSViewRepresentable wrapping MTKView
- `DisplayLayer.swift` — 14 layer types, LayerSettings (~80 props), isBuiltIn/isFileBased/isPointBased

## TF Universe Files (7 new + 7 modified)
- **`TFUniverseView.swift`** — Top-level SwiftUI view: Metal canvas overlay, node labels, camera toolbar, diagnostics/settings/shortcuts overlays. Houses `contentView`, `TFUniverseMetalView` (NSViewRepresentable), `TFNodeLabelsOverlay`, `TFUniverseToolbar`, `KeyboardShortcutsOverlay`, `TFUniverseModifiers` (ViewModifier extracting lifecycle/sheets/key handlers), `CommandKeyHandler` (⌘D/⌘,), `TFUniverseDetailPanel`.
- **`TFUniverseGraphRenderer.swift`** — Metal renderer: node/edge meshes, axis arrows, `FocusAnim` (glow ball + chain dim/brighten), `heartbeatPulse()` (4% size oscillation at 2.5Hz), `autoFitCamera()`/`animateCamera()`/`focus(on:)`, edge pulse via `currentTime`.
- **`TFUniverseMetalView.swift`** — NSViewRepresentable wrapping MTKView for TF Universe mode. Camera toolbar (WASD/Q/E/R/F/Z/X), keyboard handler, Timer polling for lost-in-space detection.
- **`TFUniverseViewModel.swift`** — `@Observable` VM: `computeDiagnostics()` + `buildRenderData()` (filter-aware dimming) + `TFMissingFrameRegistry` + `NodeDiagnostics`/`EdgeDiagnostics` + jitter tracking (60-sample rolling) + authority conflict detection + BFS connectivity + 8 `TFColorMode` cases + `activeFilter` support.
- **`TFUniverseToolbar.swift`** — Toolbar with `TFCameraToolbarView` (capsule: zoom/reset/fit/pan + ? button) + `TFDiagnosticsFilter` enum (5 filter chips) + diagnostics/settings toggle buttons.
- **`TFUniverseDetailPanel.swift`** — Detail panel: 5 collapsible sections (Position, Rotation, Diagnostics, Children, Metadata) + SparklineView + `TFColorMode` enum definition.
- **`TFCameraToolbarView.swift`** — Floating capsule toolbar at bottom-center of TF Universe view. Buttons: pan (4-dir), zoom, fit, reset + tooltip on hover + ? shortcut reference. `FocusAnim` state machine with `travelProgress`/`chainDimActive`/`deselectProgress`.
- **`TFDiagnosticsPanel.swift`** — 11-card diagnostics grid covering all diagnostic questions (Tree Structure, Missing Frames, Connectivity, Stale Detection, Position, Rotation, Publish Rate, Timestamp, Latency, Jitter, Authority).
- **`TFNodeCardView.swift`** — Hover-reveal diagnostic card: position, rotation (RPY), Hz, latency, jitter, status icon + color bar, parent/children labels.
- **`TFUniverseSettingsView.swift`** — Settings panel: Display tab (color mode, label size, grouping), Shortcuts tab (keyboard reference table).
- **`TFMissingFrameRegistry.swift`** — Expected vs active frames tracking. Triples `isMissing` flag, drives ghost node rendering.
- **Shaders/TFUniverseShaders.metal** — Node + axis arrow + edge vertex/fragment shaders. `edge_vertex_pulse`/`edge_fragment_pulse`: dashed pattern + time-based pulse for stale edges.

## Layer Types
Topic-based: laserScan, pointCloud2, occupancyGrid, octomap, image, compressedImage, odometry, markerArray, poseStamped, path
Built-in: tfFrames, robotModel
File-based: staticMap, meshMap

## Message Handlers
All follow: parse JSON → TF lookup (sensor frame → fixed frame) → swizzle coordinates → build PointCloudFrame
Coordinate: Metal(x,y,z) = (-ROS_y, ROS_z, ROS_x). Quaternion: (-ROS_qy, ROS_qz, ROS_qx, ROS_qw)

## TF Universe Design Principles
- **11 diagnostic questions** — every visual element answers a specific TF debugging question
- **Info-dense nodes** — status icons (✅ active, ⏸️ static, ⚠️ conflict, 💀 missing, 🔴 stale) + age/Hz
- **Immersive 3D** — nodes in 3D space with orbit/focus/pan camera, auto-fit, WASD keyboard controls
- **Interactive hierarchy** — click→focus 3-stage animation (fly + glow ball + stable highlight)
- **8 color modes** — byDepth, byHealth, byStaticDynamic, byRate, byLatency, byJitter, byConflict, byReachability
- **Filter chips** — 5 filters dim non-matching nodes to 12% opacity
- **Per-node diagnostics** — every node is a self-contained diagnostic dashboard
- **Edge pulse language** — green→yellow→red pulse + dash pattern for stale edges
- **Heartbeat animation** — subtle 4% size oscillation on active nodes
- **Keyboard-first** — W/A/S/D, Q/E, R/F, ⌘D, ⌘,, Esc, ? shortcuts

## Gotchas
- Handlers look up `activeLayers.first { $0.id == layerID }` at dispatch time (struct copy at subscription time would freeze settings)
- `.onChange(of: layers)` restarts subscriptions only on structural change; settings-only calls `updateLayerSettings()` (no clear)
- Nav Goal: auto-switches fixed frame to "map", publishes PoseStamped, reverse swizzle: ROS(x,y) = (hitZ, -hitX)
- File-based layers show "File" badge (not Hz badge) — check `l.type.isFileBased`
- TF frame labels: 60pt hit threshold for clustering, 16pt vertical offset stacking
- TF Universe ViewModifier: body type-check overflow — use extracted `TFUniverseModifiers` ViewModifier with broken-down helper methods
- KeyboardShortcutsOverlay needs explicit `init(onDismiss:)` — implicit memberwise init is private when struct has private stored properties
