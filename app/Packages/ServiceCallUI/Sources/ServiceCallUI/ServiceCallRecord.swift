import Foundation

/// A single entry in the call history (session-only, not persisted).
public struct ServiceCallRecord: Identifiable, Sendable {
    public let id: UUID
    public let service: String
    public let argsJSON: Data
    public let timestamp: Date
    public let success: Bool
    public let error: String?

    public init(service: String, argsJSON: Data, timestamp: Date = Date(),
                success: Bool, error: String? = nil) {
        self.id = UUID()
        self.service = service
        self.argsJSON = argsJSON
        self.timestamp = timestamp
        self.success = success
        self.error = error
    }
}
