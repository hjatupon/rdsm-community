import Foundation

/// Pure validation logic for WebSocket connection URLs — no UI dependency.
public struct URLValidator: Sendable {

    public enum ValidationResult: Sendable, Equatable {
        case valid(URL)
        case empty
        case invalidScheme(String)   // must be ws:// or wss://
        case missingHost
        case portOutOfRange(Int)     // valid range 1–65535
        case malformed(String)
    }

    public static func validate(_ raw: String) -> ValidationResult {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }

        guard let url = URL(string: trimmed), url.host != nil else {
            return .malformed(trimmed)
        }

        let scheme = url.scheme?.lowercased() ?? ""
        guard scheme == "ws" || scheme == "wss" else {
            return .invalidScheme(scheme.isEmpty ? "(none)" : scheme)
        }

        guard let host = url.host, !host.isEmpty else {
            return .missingHost
        }

        if let port = url.port {
            guard (1...65535).contains(port) else {
                return .portOutOfRange(port)
            }
        }

        return .valid(url)
    }

    /// Human-readable error string, or nil when valid/empty.
    public static func errorMessage(for result: ValidationResult) -> String? {
        switch result {
        case .valid, .empty:      return nil
        case .invalidScheme(let s): return "URL must start with ws:// or wss:// (got '\(s)://')"
        case .missingHost:         return "URL must include a host"
        case .portOutOfRange(let p): return "Port \(p) is out of range (1–65535)"
        case .malformed(let raw):  return "'\(raw)' is not a valid URL"
        }
    }
}
