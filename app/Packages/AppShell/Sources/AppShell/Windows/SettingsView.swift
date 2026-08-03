import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var services: AppServices
    @Environment(PerformanceStore.self) private var performanceStore

    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gear") }
            ViewerSettingsTab()
                .environmentObject(services)
                .tabItem { Label("Viewer", systemImage: "cube.transparent") }
            RobotModelSettingsTab()
                .environmentObject(services)
                .tabItem { Label("Robot Model", systemImage: "figure.walk.motion") }
            PerformanceSettingsTab()
                .environmentObject(services)
                .environment(performanceStore)
                .tabItem { Label("Performance", systemImage: "gauge.with.needle") }
            AboutTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(minWidth: 540, maxWidth: 540, minHeight: 360, maxHeight: 700)
    }
}

private struct GeneralSettingsTab: View {
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = true

    var body: some View {
        Form {
            Section("Onboarding") {
                Button("Reset Welcome Tour") {
                    hasSeenOnboarding = false
                }
                .help("Show the welcome flow again on next launch.")
            }
            Section("Help") {
                Link("Documentation",
                     destination: URL(string: "https://ros2studio.app/docs")!)
                Link("Report an Issue",
                     destination: URL(string: "mailto:jatupon.h@icloud.com?subject=ROS2%20Studio%20Issue")!)
            }
        }
        .formStyle(.grouped)
    }
}

private struct ViewerSettingsTab: View {
    @EnvironmentObject var services: AppServices

    var body: some View {
        Form {
            Section("Fixed Frame") {
                HStack {
                    Text("Default frame")
                    Spacer()
                    TextField("world", text: Binding(
                        get: { services.fixedFrame },
                        set: { services.fixedFrame = $0 }))
                    .textFieldStyle(.roundedBorder)
                    .monospaced()
                    .frame(maxWidth: 180)
                }
                Text("All transforms in the 3D viewer are expressed relative to this TF frame. The viewer status-bar dropdown overrides this for the current session.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Active Session") {
                LabeledContent("Available frames", value: "\(services.availableFrames.count)")
                LabeledContent("Topics", value: "\(services.availableTopics.count)")
                LabeledContent("Bridge supports clientPublish",
                               value: services.serverSupportsPublish ? "Yes" : "No")
            }
        }
        .formStyle(.grouped)
    }
}

private struct RobotModelSettingsTab: View {
    @EnvironmentObject var services: AppServices
    @State private var showingMeshFolderPicker = false

    var body: some View {
        Form {
            Section("Mesh Resolution") {
                HStack {
                    Text("Mesh root folder")
                    Spacer()
                    Text(services.userMeshRoot?.path ?? "Not set")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                HStack {
                    Button("Choose Folder…") { showingMeshFolderPicker = true }
                    Spacer()
                    if services.userMeshRoot != nil {
                        Button(role: .destructive) {
                            services.userMeshRoot = nil
                        } label: { Text("Clear") }
                    }
                }
                Text("`package://<pkg>/<rest>` is resolved best-effort under `<meshRoot>/<pkg>/<rest>`. Without a mesh root, robots with package:// references fall back to placeholder boxes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !services.robotModelWarnings.isEmpty {
                Section("Recent Warnings") {
                    ForEach(Array(services.robotModelWarnings.enumerated()), id: \.offset) { _, warning in
                        Label(warning, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.caption)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .fileImporter(
            isPresented: $showingMeshFolderPicker,
            allowedContentTypes: [.folder]
        ) { result in
            if case .success(let url) = result {
                services.userMeshRoot = url
            }
        }
    }
}

private struct AboutTab: View {
    var body: some View {
        Form {
            Section("ROS2 Studio") {
                LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                LabeledContent("Build", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—")
            }
            Section("Credits") {
                Text("Native macOS cockpit for ROS2 robotics.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Open Source Components") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Gazebo Harmonic")
                        .font(.caption.bold())
                    Text("© Open Robotics, Apache License 2.0")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Divider()
                        .padding(.vertical, 4)

                    Text("ROS2 Jazzy")
                        .font(.caption.bold())
                    Text("© Open Robotics, Apache License 2.0")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Divider()
                        .padding(.vertical, 4)

                    Text("Nav2")
                        .font(.caption.bold())
                    Text("© Nav2 Contributors, Apache License 2.0")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Divider()
                        .padding(.vertical, 4)

                    Text("slam_toolbox")
                        .font(.caption.bold())
                    Text("© Steve Macenski, LGPL 2.1")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        .formStyle(.grouped)
    }
}
