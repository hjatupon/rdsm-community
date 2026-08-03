import Foundation

/// The full serialised state of a named workspace.
///
/// `version` is bumped whenever the schema changes. ``LayoutMigrator`` handles
/// forward migration so old files always load cleanly.
public struct LayoutState: Codable, Sendable, Hashable {
    public static let currentVersion = 2

    public let version: Int
    public var panels: [PanelState]
    public var windowFrame: LayoutRect
    /// Added in v2: sidebar width in points (default 260).
    public var sidebarWidth: Double

    public init(
        version: Int = currentVersion,
        panels: [PanelState] = [],
        windowFrame: LayoutRect = LayoutRect(x: 100, y: 100, width: 1280, height: 800),
        sidebarWidth: Double = 260
    ) {
        self.version = version
        self.panels = panels
        self.windowFrame = windowFrame
        self.sidebarWidth = sidebarWidth
    }
}
