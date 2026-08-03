import SwiftUI
import ConnectionManager
import ProfileStore

/// A recent connection entry passed from the app layer to `ConnectionView`.
public struct RecentConnectionEntry: Identifiable, Sendable, Hashable {
    public let id: UUID
    public let name: String
    public let url: URL
    public let lastConnectedAt: Date

    public init(id: UUID, name: String, url: URL, lastConnectedAt: Date) {
        self.id = id
        self.name = name
        self.url = url
        self.lastConnectedAt = lastConnectedAt
    }
}

/// Sidebar connection section: shows active handles + saved profiles as one-click rows.
/// The + button creates a *new* connection only — saved profiles are surfaced here so
/// users don't have to click + (which implies "new") just to reconnect a known robot.
public struct ConnectionView: View {
    @State private var viewModel: ConnectionViewModel
    private let activeHandles: [ConnectionHandle]
    private let profileStore: ProfileStore
    private let recentConnections: [RecentConnectionEntry]
    private let onConnectResult: (@MainActor (Bool, String?) -> Void)?
    private let onSaveResult: (@MainActor (String) -> Void)?

    @State private var showingNewConnectionSheet = false
    @State private var savedProfiles: [StoredProfile] = []
    @State private var connectingProfileID: UUID? = nil
    @State private var connectingRecentID: UUID? = nil
    @State private var profileToDelete: StoredProfile? = nil

    public init(manager: ConnectionManager,
                profileStore: ProfileStore,
                activeHandles: [ConnectionHandle],
                recentConnections: [RecentConnectionEntry] = [],
                onConnectResult: (@MainActor (Bool, String?) -> Void)? = nil,
                onSaveResult: (@MainActor (String) -> Void)? = nil) {
        _viewModel = State(initialValue: ConnectionViewModel(manager: manager))
        self.profileStore = profileStore
        self.activeHandles = activeHandles
        self.recentConnections = recentConnections
        self.onConnectResult = onConnectResult
        self.onSaveResult = onSaveResult
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                activeConnectionsHeader
                activeConnectionsList
                if !recentConnectionsToShow.isEmpty {
                    recentConnectionsSection
                }
                if !savedProfiles.isEmpty {
                    savedProfilesSection
                }
            }
        }
        .task {
            await refreshProfiles()
        }
        .sheet(isPresented: $showingNewConnectionSheet) {
            NewConnectionSheet(
                viewModel: viewModel,
                profileStore: profileStore,
                onConnect: { ok, info in
                    onConnectResult?(ok, info)
                    if ok { showingNewConnectionSheet = false }
                },
                onSave: { name in
                    onSaveResult?(name)
                    Task { await refreshProfiles() }
                }
            )
        }
        .onReceive(NotificationCenter.default.publisher(
            for: Notification.Name("com.jatupon.ros2studio.focusNewConnection")
        )) { _ in
            showingNewConnectionSheet = true
        }
        .alert("Delete Profile", isPresented: Binding(
            get: { profileToDelete != nil },
            set: { if !$0 { profileToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { profileToDelete = nil }
            Button("Delete", role: .destructive) {
                if let profile = profileToDelete {
                    profileToDelete = nil
                    Task { await deleteProfile(profile) }
                }
            }
        } message: {
            if let profile = profileToDelete {
                Text("Are you sure you want to delete \"\(profile.name)\"?")
            }
        }
    }

    // MARK: - Header

    private var activeConnectionsHeader: some View {
        HStack {
            Text("Active Connections")
                .font(.headline)
            Spacer()
            Button {
                showingNewConnectionSheet = true
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("New Connection")
            .accessibilityHint("Opens the new connection form.")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Active Connections List

    /// Recent connections that are not already represented by a saved profile or active handle.
    private var recentConnectionsToShow: [RecentConnectionEntry] {
        guard activeHandles.isEmpty else { return [] }
        let savedURLs = Set(savedProfiles.map(\.url))
        return recentConnections.filter { !savedURLs.contains($0.url) }
    }

    @ViewBuilder
    private var activeConnectionsList: some View {
        if activeHandles.isEmpty {
            VStack(spacing: 6) {
                Text("No active connections")
                    .foregroundStyle(.secondary)
                    .font(.callout)
                if savedProfiles.isEmpty && recentConnectionsToShow.isEmpty {
                    Text("Tap + to connect to a robot.")
                        .foregroundStyle(.tertiary)
                        .font(.caption)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .padding(.horizontal, 16)
        } else {
            VStack(spacing: 0) {
                ForEach(activeHandles) { handle in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(handle.profile.name).font(.body)
                            Text(handle.profile.url.absoluteString)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        ConnectionStatusBadge(handle: handle)
                        Button("Disconnect") {
                            Task { await viewModel.disconnect(handle) }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    Divider().padding(.leading, 16)
                }
            }
        }
    }

    // MARK: - Recent Connections Section

    private var recentConnectionsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Recent")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 6)

            ForEach(recentConnectionsToShow) { entry in
                recentConnectionRow(entry)
                Divider().padding(.leading, 16)
            }
        }
    }

    @ViewBuilder
    private func recentConnectionRow(_ entry: RecentConnectionEntry) -> some View {
        let isActive = activeHandles.contains { $0.profile.url == entry.url }
        let isConnecting = connectingRecentID == entry.id

        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(.body)
                Text(entry.url.absoluteString)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()

            if isActive {
                Text("Connected")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else if isConnecting {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button("Connect") {
                    Task { await connectRecentEntry(entry) }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .accessibilityLabel("Connect to \(entry.name)")
                .accessibilityHint("Reconnects to \(entry.url.absoluteString)")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func connectRecentEntry(_ entry: RecentConnectionEntry) async {
        connectingRecentID = entry.id
        defer { connectingRecentID = nil }
        do {
            try await viewModel.connectProfile(name: entry.name, url: entry.url)
            onConnectResult?(true, entry.url.absoluteString)
        } catch {
            onConnectResult?(false, error.localizedDescription)
        }
    }

    // MARK: - Saved Profiles Section

    private var savedProfilesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Saved Profiles")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 6)

            ForEach(savedProfiles) { profile in
                savedProfileRow(profile)
                Divider().padding(.leading, 16)
            }
        }
    }

    @ViewBuilder
    private func savedProfileRow(_ profile: StoredProfile) -> some View {
        let isActive = activeHandles.contains { $0.profile.url == profile.url && $0.profile.name == profile.name }
        let isConnecting = connectingProfileID == profile.id

        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.name)
                    .font(.body)
                Text(profile.url.absoluteString)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()

            if isActive {
                Text("Connected")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else if isConnecting {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button("Connect") {
                    Task { await connectSavedProfile(profile) }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .accessibilityLabel("Connect to \(profile.name)")
                .accessibilityHint("Connects to \(profile.url.absoluteString)")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .contextMenu {
            Button(role: .destructive) {
                profileToDelete = profile
            } label: {
                Label("Delete Profile", systemImage: "trash")
            }
        }
    }

    // MARK: - Helpers

    private func refreshProfiles() async {
        savedProfiles = await profileStore.list()
    }

    private func connectSavedProfile(_ profile: StoredProfile) async {
        connectingProfileID = profile.id
        defer { connectingProfileID = nil }
        do {
            try await viewModel.connectProfile(name: profile.name, url: profile.url)
            onConnectResult?(true, profile.url.absoluteString)
        } catch {
            onConnectResult?(false, error.localizedDescription)
        }
    }

    private func deleteProfile(_ profile: StoredProfile) async {
        try? await profileStore.delete(profile.id)
        await refreshProfiles()
    }
}

// MARK: - New Connection Sheet

public struct NewConnectionSheet: View {
    @Bindable var viewModel: ConnectionViewModel
    private let profileStore: ProfileStore
    private let onConnect: @MainActor (Bool, String?) -> Void
    private let onSave: (@MainActor (String) -> Void)?

    private enum FocusField { case name, url }
    @FocusState private var focusedField: FocusField?
    @Environment(\.dismiss) private var dismiss

    @State private var profileSaved: Bool = false

    public init(viewModel: ConnectionViewModel,
                profileStore: ProfileStore,
                onConnect: @escaping @MainActor (Bool, String?) -> Void,
                onSave: (@MainActor (String) -> Void)? = nil) {
        self.viewModel = viewModel
        self.profileStore = profileStore
        self.onConnect = onConnect
        self.onSave = onSave
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sheetHeader
            Divider()
            formBody
                .padding(16)
        }
        .frame(minWidth: 360, idealWidth: 400, minHeight: 220)
        .task { focusedField = .name }
    }

    private var sheetHeader: some View {
        HStack {
            Text("New Connection")
                .font(.headline)
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var formBody: some View {
        VStack(alignment: .leading, spacing: 16) {

            VStack(alignment: .leading, spacing: 4) {
                Text("Name")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("e.g. Spot (Lab)", text: $viewModel.profileName)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, minHeight: 28)
                    .focused($focusedField, equals: .name)
                    .help("A friendly name to identify this robot connection")
                    .accessibilityLabel("Connection name")
                    .accessibilityHint("A friendly name for this robot connection.")
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("URL")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("ws://localhost:9090", text: $viewModel.urlText)
                    .textFieldStyle(.roundedBorder)
                    .monospaced()
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, minHeight: 28)
                    .focused($focusedField, equals: .url)
                    .help("WebSocket URL of the robot's rosbridge server (e.g. ws://robot-ip:9090)")
                    .accessibilityLabel("Robot connection URL")
                    .accessibilityHint("WebSocket URL of the robot's rosbridge server, e.g. ws://your-robot-ip:9090.")
                if let err = viewModel.urlErrorMessage {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            if let err = viewModel.lastError {
                Label(err, systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button {
                    Task { await saveProfile() }
                } label: {
                    if profileSaved {
                        Label("Saved", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Text("Save Profile")
                    }
                }
                .disabled(viewModel.urlValidation == .empty || profileSaved)
                .help("Save this connection as a reusable profile for quick access later")
                .accessibilityLabel("Save profile")
                .accessibilityHint("Saves the current URL and name as a reusable profile.")

                Spacer()

                Button {
                    Task {
                        let urlString = viewModel.urlText
                        await viewModel.connect()
                        if let err = viewModel.lastError {
                            onConnect(false, err)
                        } else {
                            onConnect(true, urlString)
                        }
                    }
                } label: {
                    if viewModel.isConnecting {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Connecting…")
                        }
                    } else {
                        Text("Connect")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canConnect)
                .help("Connect to the robot at the specified URL")
                .accessibilityLabel(viewModel.isConnecting ? "Connecting" : "Connect")
                .accessibilityHint("Connects to the robot at the URL above.")
            }
        }
    }

    private func saveProfile() async {
        guard let draft = viewModel.draftForSaving() else { return }
        let p = StoredProfile(name: draft.name, url: draft.url)
        try? await profileStore.save(p)
        profileSaved = true
        onSave?(draft.name)
        // Reset the checkmark after 2 seconds
        try? await Task.sleep(for: .seconds(2))
        profileSaved = false
    }
}
