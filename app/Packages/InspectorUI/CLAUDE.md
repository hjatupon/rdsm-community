# InspectorUI — Schema-Driven Topic Inspector

## Key Files (19 Swift files)
- `InspectorView.swift` (497 lines) — header (Hz/count/pin), throttle bar (pause/rate/visual-raw/reset), content dispatch
- `InspectorViewModel.swift` (534 lines) — @Observable @MainActor, subscription lifecycle, typed state per RenderKind
- `FieldNode.swift` (122 lines) — recursive JSON tree model (id/key/displayValue/children/arraySummary)
- `JSONTreeView.swift` (246 lines) — always-expanded tree (ScrollView+LazyVStack, not List to avoid collapse-reset)
- `RenderKind.swift` (83 lines) — 17-valued enum, RenderKindResolver maps schemaName → RenderKind
- `ROS2CDRDecoder.swift` (270 lines) — binary CDR decoder with encapsulation header

## RenderKind (17 values)
image, numericScalar, boolean, stringValue, logMessage, rangeGauge, batteryState, laserScan, odometry, imu, twist, occupancyGrid, jointState, diagnosticArray, tfTree, jsonTree

## Purpose-Built Views
BoolIndicatorView (96pt green/red circle), StringValueView, LogListView (severity pills + node/search filters + auto-scroll), RangeGaugeView (capsule gauge), BatteryStateView (icon+%), NumericChartView (ChartingCore + stats bar), LaserScanView (polar Canvas), OdometryView (dashboard + 2D trail + chart), ImuView (arc gauges), TwistView (gauges + rotational dial), JointStateView (bars), DiagnosticArrayView (status list + expandable keys), OccupancyGridInspectorView (grayscale minimap), ImageInspectorView (RGBA8/RGB8/BGRA8/mono8), JSONTreeView (always-expanded)

## Gotchas
- `.id(topic.name)` on InspectorView forces full recreation on topic switch — NEVER remove this
- Message throttle: paused (gate all display) + rateSeconds (min interval) — Hz/count update regardless
- Always-expanded tree: recursive NodeTreeView in ScrollView+LazyVStack (NOT List(children:) — List resets expand on every UUID rebuild)
- FieldNode gets new UUIDs per message → List would collapse every frame
