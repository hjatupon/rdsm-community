import AppKit
import SwiftUI

/// Handles app-level lifecycle events that SwiftUI doesn't expose.
/// Covers two disconnect triggers:
///   1. Red-button / Cmd+W window close (app stays alive, all windows gone)
///   2. Cmd+Q / Force Quit (app terminates)
public final class AppDelegate: NSObject, NSApplicationDelegate {
    public override init() { super.init() }
    /// Populated by ROS2StudioApp on first window appear.
    nonisolated(unsafe) static weak var services: AppServices?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Disable automatic window tabbing so "Show Tab Bar" / "Show All Tabs"
        // never appear in the View menu.
        NSWindow.allowsAutomaticWindowTabbing = false

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWindowClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWindowResize(_:)),
            name: NSWindow.didResizeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWindowMove(_:)),
            name: NSWindow.didMoveNotification,
            object: nil
        )
    }

    @objc private func handleWindowResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window.minSize.width >= 1000
        else { return }
        WindowFrameStore.save(frame: window.frame)
    }

    @objc private func handleWindowMove(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window.minSize.width >= 1000
        else { return }
        WindowFrameStore.save(frame: window.frame)
    }

    /// Fires when any NSWindow is about to close. We filter to the main content
    /// window by checking minimum width — the main WindowGroup sets minWidth: 1100,
    /// while the Settings window is a standard small panel.
    @objc private func handleWindowClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window.minSize.width >= 1000
        else { return }
        WindowFrameStore.save(frame: window.frame)
        Task { @MainActor in
            await AppDelegate.services?.disconnectAll()
        }
    }

    /// ROS2 Studio is effectively a single-window app (Settings is a small
    /// auxiliary panel, not a primary window). Per App Review guideline 4.0.0,
    /// a single-window app should quit when its main window closes rather than
    /// leave the user with no way to reopen it.
    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            // No windows visible — open the main WindowGroup again.
            // This handles dock click, ⌘N, and menu items after ⌘W.
            for scene in NSApp.windows where scene.minSize.width >= 1000 {
                scene.makeKeyAndOrderFront(nil)
                return true
            }
            // If no matching window found, let SwiftUI create one via WindowGroup
            for window in NSApp.windows {
                if window.canBecomeKey {
                    window.makeKeyAndOrderFront(nil)
                    return true
                }
            }
        }
        return true
    }

    public func applicationWillTerminate(_ notification: Notification) {
        if let window = NSApp.keyWindow, window.minSize.width >= 1000 {
            WindowFrameStore.save(frame: window.frame)
        }
        Task { @MainActor in
            await AppDelegate.services?.disconnectAll()
        }
    }
}
