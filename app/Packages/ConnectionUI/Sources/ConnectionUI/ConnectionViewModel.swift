import Foundation
import Observation
import ConnectionManager

/// View-model for the New Connection sheet. Holds draft form state and drives
/// ConnectionManager connect/disconnect calls.
///
/// Active-handle observation was removed — AppServices is the single long-lived
/// iterator of ConnectionManager.connections and exposes activeConnectionHandles
/// as @Published. ConnectionView reads that value directly, avoiding the
/// AsyncStream single-iterator problem.
@Observable
@MainActor
public final class ConnectionViewModel {

    // MARK: - Draft fields

    public var urlText: String = "ws://localhost:9090"
    public var profileName: String = ""

    // MARK: - Derived validation

    public var urlValidation: URLValidator.ValidationResult {
        URLValidator.validate(urlText)
    }

    public var urlErrorMessage: String? {
        URLValidator.errorMessage(for: urlValidation)
    }

    public var canConnect: Bool {
        if case .valid = urlValidation { return !isConnecting }
        return false
    }

    // MARK: - Live state

    public private(set) var isConnecting: Bool = false
    public private(set) var lastError: String? = nil

    // MARK: - Private

    private let manager: ConnectionManager

    public init(manager: ConnectionManager) {
        self.manager = manager
    }

    // MARK: - Actions

    public func connect() async {
        guard case .valid(let url) = urlValidation else { return }
        lastError = nil
        isConnecting = true
        defer { isConnecting = false }

        let name = profileName.isEmpty ? (url.host ?? "connection") : profileName
        let profile = ManagerProfile(name: name, url: url)

        do {
            _ = try await manager.connect(profile)
        } catch {
            lastError = error.localizedDescription
        }
    }

    public func disconnect(_ handle: ConnectionHandle) async {
        try? await manager.disconnect(handle)
    }

    /// Connect directly from a saved profile (bypasses draft form state).
    public func connectProfile(name: String, url: URL) async throws {
        lastError = nil
        isConnecting = true
        defer { isConnecting = false }
        let profile = ManagerProfile(name: name, url: url)
        _ = try await manager.connect(profile)
    }

    /// Returns the current draft as a (name, URL) pair for the caller to persist.
    public func draftForSaving() -> (name: String, url: URL)? {
        guard case .valid(let url) = urlValidation else { return nil }
        let name = profileName.isEmpty ? (url.host ?? "profile") : profileName
        return (name, url)
    }
}
