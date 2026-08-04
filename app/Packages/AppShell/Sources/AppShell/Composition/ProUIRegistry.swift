import SwiftUI
import Foundation
import TopicStore
import Transport
import PublishService
import PublishUI

// MARK: - Shared app paths (core)

/// Central Application Support location, shared by the shell and by Pro features
/// that persist their own state (parameter profiles, templates, bookmarks).
public enum AppPaths {
    public static var appSupport: URL {
        let url = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ROS2Studio", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

// MARK: - Session lifecycle (open-core seam)

/// Observes the shell's session lifecycle so Pro features can wire/unwire their
/// own state on connect / replay-load / disconnect without the shell
/// (`AppServices`) importing any Pro package.
@MainActor
public protocol SessionLifecycleObserver: AnyObject {
    /// A live session became active with the given topic store.
    func sessionDidStart(store: TopicStore, topics: [TopicDescriptor])
    /// The active session is being torn down.
    func sessionWillEnd()
}

// MARK: - Pro UI plugin registry (open-core seam)

/// Stable identifiers for the right-panel tabs. Used as registry keys so the
/// shell can look up injected Pro content without referencing Pro types.
public enum RightPanelTabID {
    public static let inspector  = "inspector"
    public static let parameters = "parameters"
    public static let tfTree     = "tfTree"
    public static let monitor    = "monitor"
    public static let plot       = "plot"
    public static let services   = "services"
}

/// Everything a right-panel content builder might need, passed fresh each render.
/// Carries only shell/core types so this file stays free of Pro dependencies.
@MainActor
public struct RightPanelContext {
    /// Composition root. Pro builders read their own Pro-typed services off this
    /// inside the Pro registration file, the only place that imports Pro packages.
    public let services: AppServices
    /// Active topic store, or nil when disconnected.
    public let store: TopicStore?
    /// Current replay position in seconds (0 in live mode) — for time-synced panels.
    public let currentBagTimeSec: Double

    init(services: AppServices, store: TopicStore?, currentBagTimeSec: Double) {
        self.services = services
        self.store = store
        self.currentBagTimeSec = currentBagTimeSec
    }
}

/// Inputs the Publish sheet needs — all core types. The Pro build wraps these in
/// a sheet that adds the templates sidebar; the free build uses a templates-free one.
@MainActor
public struct PublishSheetContext {
    public let publishService: PublishService?
    public let topics: [TopicDescriptor]
    public let isEnabled: Bool
    public let formState: PublishFormState

    init(publishService: PublishService?, topics: [TopicDescriptor], isEnabled: Bool, formState: PublishFormState) {
        self.publishService = publishService
        self.topics = topics
        self.isEnabled = isEnabled
        self.formState = formState
    }
}

/// Registry of Pro-contributed UI, keyed by a stable id. The free (Community)
/// build registers nothing here, so Pro surfaces are simply absent; the paid (Pro)
/// build populates it at launch via `registerProPlugins()`.
@MainActor
public final class ProUIRegistry {
    public static let shared = ProUIRegistry()
    private init() {}

    private var panelBuilders: [String: @MainActor (RightPanelContext) -> AnyView] = [:]

    /// Register (or replace) the content builder for a right-panel tab.
    public func registerPanel(id: String, _ build: @escaping @MainActor (RightPanelContext) -> AnyView) {
        panelBuilders[id] = build
    }

    /// Whether a Pro panel has been registered for `id`.
    public func hasPanel(id: String) -> Bool { panelBuilders[id] != nil }

    /// Build the registered panel for `id`, or nil if none is registered.
    public func makePanel(id: String, context: RightPanelContext) -> AnyView? {
        panelBuilders[id]?(context)
    }

    // MARK: - Session lifecycle observers

    private var sessionObservers: [SessionLifecycleObserver] = []

    /// Register a Pro feature to receive session lifecycle callbacks.
    public func addSessionObserver(_ observer: SessionLifecycleObserver) {
        sessionObservers.append(observer)
    }

    public func notifySessionDidStart(store: TopicStore, topics: [TopicDescriptor]) {
        sessionObservers.forEach { $0.sessionDidStart(store: store, topics: topics) }
    }

    public func notifySessionWillEnd() {
        sessionObservers.forEach { $0.sessionWillEnd() }
    }

    // MARK: - Publish sheet

    private var publishSheetBuilder: (@MainActor (PublishSheetContext) -> AnyView)?

    public func registerPublishSheet(_ build: @escaping @MainActor (PublishSheetContext) -> AnyView) {
        publishSheetBuilder = build
    }

    public func makePublishSheet(context: PublishSheetContext) -> AnyView? {
        publishSheetBuilder?(context)
    }

    // MARK: - Recording toolbar

    private var recordingToolbarBuilder: (@MainActor (AppServices) -> AnyView)?

    public func registerRecordingToolbar(_ build: @escaping @MainActor (AppServices) -> AnyView) { recordingToolbarBuilder = build }
    public func makeRecordingToolbar(services: AppServices) -> AnyView? { recordingToolbarBuilder?(services) }
}
