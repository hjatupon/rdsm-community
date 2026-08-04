import SwiftUI

/// The application's root scene — WindowGroup + menu commands.
///
/// Shared by both editions: the per-edition `@main` App wraps this scene (and, in the
/// paid build only, calls `registerProPlugins()` in its init). Everything the scene
/// uses (AppServices, MainWindow) stays internal to AppShell.
public struct AppRootScene: Scene {
    @StateObject private var services = AppServices()
    @State private var showOnboarding = false

    public init() {}

    public var body: some Scene {
        WindowGroup {
            MainWindow()
                .environmentObject(services)
                .frame(minWidth: WindowFrameStore.minWidth, maxWidth: .infinity,
                       minHeight: WindowFrameStore.minHeight, maxHeight: .infinity)
                .preferredColorScheme(.dark)
                .task {
                    await services.startObservingConnections()
                }
                .onAppear {
                    // Give AppDelegate a reference for window-close + Cmd+Q disconnect
                    AppDelegate.services = services
                    // Live-only edition: show the welcome flow on first launch.
                    if !UserDefaults.standard.bool(forKey: "hasSeenOnboarding") {
                        showOnboarding = true
                    }
                    // Restore window origin from saved frame, or center on screen
                    if let window = NSApp.windows.first(where: { $0.minSize.width >= 1000 }) {
                        if let saved = WindowFrameStore.load() {
                            window.setFrameOrigin(saved.origin)
                        } else {
                            window.center()
                        }
                    }
                }
                .sheet(isPresented: $showOnboarding) {
                    OnboardingFlow(isPresented: $showOnboarding)
                }
                .accentColor(.ros2Accent)
        }
        .defaultSize(WindowFrameStore.savedSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Connection…") {
                    NotificationCenter.default.post(
                        name: Notification.Name("com.jatupon.ros2studio.focusNewConnection"), object: nil)
                }
                .keyboardShortcut("n", modifiers: [.command])

                Divider()

                Button("Disconnect") { Task { await services.disconnectAll() } }
                    .keyboardShortcut("d", modifiers: [.command, .control])
                    .disabled(services.activeConnectionHandles.isEmpty)
            }

            // View menu — tab switching + camera
            CommandGroup(after: .toolbar) {
                Divider()
                Button("Inspector") {
                    NotificationCenter.default.post(name: Notification.Name("com.jatupon.ros2studio.openPanel"), object: "inspector")
                }
                .keyboardShortcut("1", modifiers: [.command])

                Button("Parameters") {
                    NotificationCenter.default.post(name: Notification.Name("com.jatupon.ros2studio.openPanel"), object: "parameters")
                }
                .keyboardShortcut("2", modifiers: [.command])

                Button("TF Tree") {
                    NotificationCenter.default.post(name: Notification.Name("com.jatupon.ros2studio.openPanel"), object: "tf_tree")
                }
                .keyboardShortcut("3", modifiers: [.command])

                Divider()

                Button("Reset Camera") {
                    services.toasts.show(.info, title: "Reset Camera",
                                         message: "Press R inside the 3D viewer to reset.")
                }
                .keyboardShortcut("r", modifiers: [])
            }

            // Help menu — replace defaults with useful links
            CommandGroup(replacing: .help) {
                Button("\(AppInfo.displayName) Documentation") {
                    NSWorkspace.shared.open(AppInfo.docsURL)
                }
                Button("Report an Issue") {
                    if let url = URL(string: "mailto:jatupon.h@icloud.com?subject=RDSM%20Issue") {
                        NSWorkspace.shared.open(url)
                    }
                }
                Button("Send Feedback") {
                    if let url = URL(string: "mailto:jatupon.h@icloud.com?subject=RDSM%20Feedback") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }

        }
    }
}
