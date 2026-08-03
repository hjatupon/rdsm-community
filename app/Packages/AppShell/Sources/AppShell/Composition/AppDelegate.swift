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

        // Editions without a Settings window (Community) must not show the
        // "Settings…" item. SwiftUI provides no supported way to drop it while a
        // `Settings` scene exists (CommandGroup(replacing: .appSettings) does not
        // override the scene-provided item), so remove it from the app menu directly.
        // SwiftUI adds the item after launch and may re-add it when it rebuilds the
        // menu, so keep sweeping for a while rather than removing once.
        MainActor.assumeIsolated {
            if !AppCapabilities.shared.settingsWindowEnabled {
                AppDelegate.startStrippingSettingsMenuItem()
            }
        }
    }

    /// Re-strip immediately when the app regains focus (a common moment for SwiftUI
    /// to have rebuilt the menu while inactive), so the item never lingers a frame.
    public func applicationDidBecomeActive(_ notification: Notification) {
        MainActor.assumeIsolated {
            if !AppCapabilities.shared.settingsWindowEnabled {
                _ = AppDelegate.removeSettingsMenuItemNow()
            }
        }
    }

    /// Keeps the Settings item out of the app menu for the app's lifetime.
    ///
    /// SwiftUI re-adds the item whenever it rebuilds the menu (e.g. when a bound
    /// command's state changes on connect/disconnect), and offers no API to suppress
    /// it while a `Settings` scene exists. Removing it once is therefore not enough.
    /// A 0.5s sweep is far below the cost of noticing — it walks ~7 static menus — and
    /// runs only in editions that hide Settings (Community); the paid build never
    /// starts it.
    @MainActor
    private static func startStrippingSettingsMenuItem() {
        _ = removeSettingsMenuItemNow()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            MainActor.assumeIsolated { startStrippingSettingsMenuItem() }
        }
    }

    /// Removes the Settings/Preferences item from whichever top-level menu holds it
    /// (normally the app menu). Returns whether it was found and removed.
    @MainActor
    @discardableResult
    private static func removeSettingsMenuItemNow() -> Bool {
        guard let mainMenu = NSApp.mainMenu else { return false }
        let settingsSelectors: Set<Selector> = [
            Selector(("showSettingsWindow:")),
            Selector(("showPreferencesWindow:")),
            Selector(("orderFrontStandardPreferencesPanel:"))
        ]
        let matches: (NSMenuItem) -> Bool = { item in
            (item.action.map { settingsSelectors.contains($0) } ?? false)
                || item.title.hasPrefix("Settings")
                || item.title.hasPrefix("Preferences")
        }
        for topItem in mainMenu.items {
            guard let submenu = topItem.submenu,
                  let idx = submenu.items.firstIndex(where: matches)
            else { continue }
            submenu.removeItem(at: idx)
            // Collapse a now-doubled separator left behind by the removal.
            if idx < submenu.items.count, submenu.items[idx].isSeparatorItem,
               idx > 0, submenu.items[idx - 1].isSeparatorItem {
                submenu.removeItem(at: idx)
            }
            return true
        }
        return false
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
