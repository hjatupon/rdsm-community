import SwiftUI
import AppShell

/// RDSM Community — free, open-source edition. Thin wrapper over the shared
/// `AppRootScene` from AppShell. No Pro plugins are registered, so advanced
/// features (rosbag, plot, parameter profiles, inspector visualizations,
/// TF Universe, templates) are absent by construction.
@main
struct RDSMCommunityApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        // Lean edition: hides rosbag replay, the Services tab, the performance
        // tools, and the Settings window. Set before any scene renders. The Pro
        // @main leaves the default (.full), so it is unaffected.
        AppCapabilities.shared.edition = .community
    }

    var body: some Scene {
        AppRootScene()
    }
}
