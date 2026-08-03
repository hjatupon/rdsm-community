import SwiftUI

/// The application's root scene — WindowGroup + menu commands + Settings.
///
/// Shared by both editions: the per-edition `@main` App wraps this scene (and, in the
/// paid build only, calls `registerProPlugins()` in its init). Everything the scene
/// uses (AppServices, MainWindow, performance stores) stays internal to AppShell.
public struct AppRootScene: Scene {
    @StateObject private var services = AppServices()
    @State private var performanceStore = PerformanceStore()
    @State private var dashboard = PerformanceDashboard()
    @State private var showOnboarding = false
    @State private var showModeSelector = false

    public init() {}

    public var body: some Scene {
        WindowGroup {
            MainWindow()
                .environmentObject(services)
                .environment(performanceStore)
                .environment(dashboard)
                .frame(minWidth: WindowFrameStore.minWidth, maxWidth: .infinity,
                       minHeight: WindowFrameStore.minHeight, maxHeight: .infinity)
                .preferredColorScheme(.dark)
                .task {
                    await services.startObservingConnections()
                }
                .task {
                    dashboard.start()
                }
                .onAppear {
                    // Give AppDelegate a reference for window-close + Cmd+Q disconnect
                    AppDelegate.services = services
                    if AppCapabilities.shared.rosbagEnabled {
                        if !UserDefaults.standard.bool(forKey: "hasSeenModeSelector") {
                            showModeSelector = true
                        }
                    } else {
                        // Community: there is no replay mode to choose. Go straight to
                        // the live cockpit and show the welcome flow on first launch.
                        if !UserDefaults.standard.bool(forKey: "hasSeenOnboarding") {
                            showOnboarding = true
                        }
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
                .onChange(of: services.activeConnectionHandles.isEmpty) { _, isEmpty in
                    if !isEmpty {
                        UserDefaults.standard.set(true, forKey: "hasSeenModeSelector")
                    }
                }
                .onReceive(NotificationCenter.default.publisher(
                    for: Notification.Name("com.jatupon.ros2studio.showModeSelector")
                )) { _ in
                    showModeSelector = true
                }
                .sheet(isPresented: $showModeSelector) {
                    ModeSelectorView(isPresented: $showModeSelector) { mode in
                        services.setMode(mode)
                        if !UserDefaults.standard.bool(forKey: "hasSeenOnboarding") {
                            showOnboarding = true
                        }
                    }
                }
                .sheet(isPresented: $showOnboarding) {
                    OnboardingFlow(isPresented: $showOnboarding)
                }
                .accentColor(.ros2Accent)
                .onReceive(NotificationCenter.default.publisher(
                    for: NSNotification.Name("NSProcessInfoPowerStateDidChange")
                )) { _ in
                    if performanceStore.autoEcoOnBattery,
                       ProcessInfo.processInfo.isLowPowerModeEnabled {
                        performanceStore.applyPreset(.eco)
                    }
                }
        }
        .defaultSize(WindowFrameStore.savedSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Connection…") {
                    if services.sessionMode == .replay {
                        services.setMode(.live)
                    }
                    NotificationCenter.default.post(
                        name: Notification.Name("com.jatupon.ros2studio.focusNewConnection"), object: nil)
                }
                .keyboardShortcut("n", modifiers: [.command])
                .disabled(services.sessionMode != .live && services.activeConnectionHandles.isEmpty)

                if AppCapabilities.shared.rosbagEnabled {
                    Button("Open Rosbag…") {
                        if services.sessionMode == .live {
                            services.setMode(.replay)
                        }
                        NotificationCenter.default.post(
                            name: Notification.Name("com.jatupon.ros2studio.openRosbag"), object: nil)
                    }
                    .keyboardShortcut("o", modifiers: [.command])
                }

                Divider()

                Button("Disconnect") { Task { await services.disconnectAll() } }
                    .keyboardShortcut("d", modifiers: [.command, .control])
                    .disabled(services.activeConnectionHandles.isEmpty)

                if AppCapabilities.shared.rosbagEnabled {
                    Divider()

                    Button("Choose Session Mode…") {
                        NotificationCenter.default.post(
                            name: Notification.Name("com.jatupon.ros2studio.showModeSelector"), object: nil)
                    }
                    .keyboardShortcut("m", modifiers: [.command, .shift])
                }
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
                .disabled(services.sessionMode == .replay)

                Button("TF Tree") {
                    NotificationCenter.default.post(name: Notification.Name("com.jatupon.ros2studio.openPanel"), object: "tf_tree")
                }
                .keyboardShortcut("3", modifiers: [.command])

                if AppCapabilities.shared.rosbagEnabled {
                    Divider()

                    Button("ROS Bag Manager…") {
                        NotificationCenter.default.post(
                            name: Notification.Name("com.jatupon.ros2studio.openBagManager"),
                            object: nil)
                    }
                    .keyboardShortcut("b", modifiers: [.command, .shift])
                }

                Divider()

                Button("Reset Camera") {
                    services.toasts.show(.info, title: "Reset Camera",
                                         message: "Press R inside the 3D viewer to reset.")
                }
                .keyboardShortcut("r", modifiers: [])
            }

            if AppCapabilities.shared.rosbagEnabled {
                CommandMenu("Bookmarks") {
                    Button("Add Bookmark") {
                        NotificationCenter.default.post(
                            name: Notification.Name("ros2studio.addBookmark"), object: nil)
                    }
                    .keyboardShortcut("b", modifiers: [])
                    .disabled(!services.isReplayActive)

                    Button("Jump to Previous Bookmark") {
                        NotificationCenter.default.post(
                            name: Notification.Name("ros2studio.previousBookmark"), object: nil)
                    }
                    .keyboardShortcut("[", modifiers: [])
                    .disabled(!services.isReplayActive)

                    Button("Jump to Next Bookmark") {
                        NotificationCenter.default.post(
                            name: Notification.Name("ros2studio.nextBookmark"), object: nil)
                    }
                    .keyboardShortcut("]", modifiers: [])
                    .disabled(!services.isReplayActive)
                }
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

        // The Settings scene stays unconditional (SwiftUI's SceneBuilder does not
        // allow a runtime `if` around a scene, and CommandGroup(replacing: .appSettings)
        // does not override the item the scene itself contributes). The Community
        // edition instead removes the "Settings…" menu item from AppKit at launch (see
        // AppDelegate), so this window has no entry point there.
        Settings {
            SettingsView()
                .environmentObject(services)
                .environment(performanceStore)
                .environment(dashboard)
        }
    }
}
