import Foundation

public enum ProfileStoreError: Error, Sendable {
    case profileNotFound(UUID)
    case encodingFailed(String)
    case decodingFailed(String)
    case ioFailed(String)
}
