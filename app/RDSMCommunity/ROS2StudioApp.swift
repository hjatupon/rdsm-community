import SwiftUI
import AppShell

/// RDSM Community — free, open-source edition. Thin wrapper over the shared
/// `AppRootScene` from AppShell. No Pro plugins are registered, so advanced
/// features (rosbag, plot, parameter profiles, inspector visualizations,
/// TF Universe, templates) are absent by construction.
@main
struct RDSMCommunityApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        AppRootScene()
    }
}
