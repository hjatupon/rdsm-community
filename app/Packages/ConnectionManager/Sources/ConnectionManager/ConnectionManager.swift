import Foundation
import Logging
import Transport

/// Central actor that manages named connection profiles and live handles.
///
/// ## Deduplication
/// Only one handle per URL is permitted at a time. Attempting to ``connect(_:)``
/// while a handle with the same URL is active throws ``ConnectionManagerError/alreadyConnected(_:)``.
///
/// ## Lifecycle broadcast
/// `connections` emits the full current handle list on every change (connect / disconnect).
/// SwiftUI views observe this stream to update connection-status badges.
public actor ConnectionManager {

    // MARK: - Public state

    /// All currently active handles, emitted on every change.
    public let connections: AsyncStream<[ConnectionHandle]>

    // MARK: - Private

    private var handles: [UUID: ConnectionHandle] = [:]
    private var urlIndex: [URL: UUID] = [:]           // dedup guard
    private let continuation: AsyncStream<[ConnectionHandle]>.Continuation
    private let profileStore: any ProfileStoreProtocol
    private let transportFactory: @Sendable (ConnectionProfile) -> any TransportClient
    private let logger: any LoggerProtocol

    // MARK: - Init

    public init(
        profileStore: any ProfileStoreProtocol = InMemoryProfileStore(),
        transportFactory: @escaping @Sendable (ConnectionProfile) -> any TransportClient,
        logger: any LoggerProtocol = NullLogger()
    ) {
        var cont: AsyncStream<[ConnectionHandle]>.Continuation!
        self.connections = AsyncStream { cont = $0 }
        self.continuation = cont
        self.profileStore = profileStore
        self.transportFactory = transportFactory
        self.logger = logger
    }

    // MARK: - Connect / Disconnect

    /// Opens a new connection for `profile`.
    ///
    /// Throws ``ConnectionManagerError/alreadyConnected(_:)`` if a handle for the
    /// same URL already exists.
    @discardableResult
    public func connect(_ profile: ConnectionProfile) async throws -> ConnectionHandle {
        if urlIndex[profile.url] != nil {
            logger.warning("ConnectionManager: duplicate connect attempt for \(profile.url)", fields: [])
            throw ConnectionManagerError.alreadyConnected(profile.url)
        }

        let transport = transportFactory(profile)
        do {
            try await transport.connect(url: profile.url)
        } catch {
            throw ConnectionManagerError.connectFailed(error.localizedDescription)
        }

        let handle = ConnectionHandle(id: UUID(), profile: profile, transport: transport)
        handles[handle.id] = handle
        urlIndex[profile.url] = handle.id
        logger.info("ConnectionManager: connected \(profile.name) → \(profile.url)", fields: [])
        broadcast()
        return handle
    }

    /// Closes the connection for `handle` and removes it from the active set.
    public func disconnect(_ handle: ConnectionHandle) async throws {
        guard handles[handle.id] != nil else {
            throw ConnectionManagerError.unknownHandle(handle.id)
        }
        await handle.transport.disconnect()
        handles.removeValue(forKey: handle.id)
        urlIndex.removeValue(forKey: handle.profile.url)
        logger.info("ConnectionManager: disconnected \(handle.profile.name)", fields: [])
        broadcast()
    }

    /// Disconnects all active handles then reconnects each in order.
    public func reconnectAll() async {
        let snapshot = Array(handles.values)
        for h in snapshot {
            try? await disconnect(h)
        }
        for h in snapshot {
            _ = try? await connect(h.profile)
        }
    }

    /// Returns a snapshot of all active handles.
    public var activeHandles: [ConnectionHandle] {
        Array(handles.values)
    }

    // MARK: - Profile persistence

    /// Loads profiles from the store without connecting.
    public func loadedProfiles() async -> [ConnectionProfile] {
        await profileStore.load()
    }

    /// Persists the given profiles without changing active connections.
    public func saveProfiles(_ profiles: [ConnectionProfile]) async {
        await profileStore.save(profiles)
    }

    // MARK: - Private

    private func broadcast() {
        continuation.yield(Array(handles.values))
    }
}

// MARK: - NullLogger

public struct NullLogger: LoggerProtocol, Sendable {
    public init() {}
    public func debug(_ message: String, fields: [LogField]) {}
    public func info(_ message: String, fields: [LogField]) {}
    public func warning(_ message: String, fields: [LogField]) {}
    public func error(_ message: String, fields: [LogField]) {}
}
