import Foundation

/// Which edition is running. Both editions share this `AppShell` package (the Pro
/// app consumes it via SwiftPM), so per-edition differences are expressed as
/// capability flags rather than by deleting code — deleting would also strip the
/// feature from Pro, which imports these same files.
public enum AppEdition: Sendable {
    /// Free, open-source edition. Ships a deliberately lean shell.
    case community
    /// Paid edition (default). Full shell — every surface visible; advanced
    /// behaviour is still supplied at runtime via `ProUIRegistry` plugins.
    case full
}

/// Process-wide edition capabilities, read from SwiftUI view/scene/command bodies.
///
/// Set once at launch from the app's `@main` init (before any scene renders) and
/// never mutated afterwards, so plain reads in view bodies are safe and do not need
/// to be observable. The Community `@main` sets `.community`; the Pro `@main` leaves
/// the default `.full`, so Pro requires no change when it bumps this dependency.
@MainActor
public final class AppCapabilities {
    public static let shared = AppCapabilities()
    private init() {}

    public var edition: AppEdition = .full

    /// Rosbag replay mode and its entry points (session-mode switch, Open Rosbag,
    /// bag manager, bookmarks, mode selector). The replay *engine* is a Pro plugin;
    /// these are just the shell affordances that must not appear without it.
    public var rosbagEnabled: Bool { edition == .full }

    /// The "Services" right-panel tab (ROS2 service browser/caller).
    public var servicesEnabled: Bool { edition == .full }

    /// The performance HUD (footer bar + pop-up panel), the "Monitor" tab, and the
    /// Performance settings tab. `PerformanceStore` itself is always present so the
    /// 3D viewport still gets render-quality values; only its UI is gated.
    public var performanceToolsEnabled: Bool { edition == .full }

    /// The Settings / Preferences window (⌘,). When disabled, macOS shows no
    /// "Settings…" item because the `Settings` scene is omitted entirely.
    public var settingsWindowEnabled: Bool { edition == .full }
}
