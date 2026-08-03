import Foundation

public enum LayoutEngineError: Error, Sendable, Equatable {
    case layoutNotFound(String)
    case encodingFailed(String)
    case decodingFailed(String)
    case ioFailed(String)
    case migrationFailed(String)
}
