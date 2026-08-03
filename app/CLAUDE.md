# ROS2 Studio — App Target

Build: `cd app && xcodegen generate --spec project.yml && xcodebuild -project ROS2Studio.xcodeproj -scheme ROS2Studio build`

## Entry Points
- `ROS2Studio/ROS2StudioApp.swift` — @main, WindowGroup, Commands (⌘N/⌘O/⌃⌘D/⌘1/2/3), Settings
- `ROS2Studio/Composition/AppServices.swift` — Single composition root, 15+ properties
- `ROS2Studio/Composition/AppDelegate.swift` — NSApplicationDelegate, window frame save/restore, close→disconnect

## Layout (MainWindow.swift)
- HSplitView: left 3D viewer (min 480) + right panel (min 320)
- VSplitView inside left: 3D viewport (top) + log panel (bottom, min 80)
- Right panel: segmented picker (Inspector | Parameters | TF Tree)
- Rosbag player: safeAreaInset bottom bar

## Patterns
- Single composition root (AppServices), `.environmentObject` injection
- NotificationCenter for decoupled routing (menu → panel)
- AsyncStream owned by ViewModel (NOT view `.task`) — single-iterator constraint
- Per-profile 3D viewer config via UserDefaults keyed by `"name|url"`
