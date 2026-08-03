# PublishUI — Publish Message Panel

## Key Types
- `PublishView` (SwiftUI) — topic field, message type picker (String/Twist/TwistStamped/Raw JSON), conditional editors
- `PublishFormState` (@MainActor ObservableObject) — form fields, MessageKind enum

## Message Type Editors
- String: TextEditor for free-form text
- Twist: 6 numeric fields (linear x/y/z, angular x/y/z)
- TwistStamped: same 6 fields (different wire format)
- Raw JSON: message type TextField + JSON TextEditor

## Files
- `PublishView.swift` (245 lines), `PublishFormState.swift` (30 lines)

## Integration
- MainWindow: PublishSheetPanel wraps PublishView in sheet
- Result via NotificationCenter "com.jatupon.ros2studio.publishResult"
- Disabled when no active connection or bridge lacks clientPublish
