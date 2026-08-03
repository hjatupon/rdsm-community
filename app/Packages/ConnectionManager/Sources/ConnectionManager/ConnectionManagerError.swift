import Foundation

public enum ConnectionManagerError: Error, Sendable, Equatable {
    /// A connection to this URL is already active.
    case alreadyConnected(URL)
    /// No active connection found for the given handle.
    case unknownHandle(UUID)
    /// The underlying transport failed to connect.
    case connectFailed(String)
}

extension ConnectionManagerError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .alreadyConnected(let url):
            return "Already connected to \(url.host ?? url.absoluteString)."
        case .unknownHandle:
            return "Connection not found."
        case .connectFailed(let reason):
            return reason
        }
    }
}
