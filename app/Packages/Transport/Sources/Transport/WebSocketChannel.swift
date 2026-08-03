import Foundation

// MARK: - WebSocket abstraction (injectable for tests)

/// A single received WebSocket frame.
enum WebSocketFrame: Equatable {
    case text(String)
    case binary(Data)
}

/// An open, bidirectional WebSocket connection.
///
/// Abstracted so ``ConnectionActor`` can be driven by a fake in tests without a
/// real network or `URLSession`.
protocol WebSocketChannel: Sendable {
    func send(_ frame: WebSocketFrame) async throws
    /// Awaits the next frame. Throws when the connection drops.
    func receive() async throws -> WebSocketFrame
    func close() async
}

/// Opens ``WebSocketChannel`` connections. Injected into ``ConnectionActor``.
protocol WebSocketConnecting: Sendable {
    func connect(url: URL, subprotocols: [String]) async throws -> any WebSocketChannel
}

// MARK: - URLSession-backed implementation

/// Production connector built on `URLSessionWebSocketTask`.
struct URLSessionWebSocketConnector: WebSocketConnecting {
    func connect(url: URL, subprotocols: [String]) async throws -> any WebSocketChannel {
        let configuration = URLSessionConfiguration.default
        let session = URLSession(configuration: configuration)
        // The `protocols:` overload makes URLSession both send the subprotocols and
        // track them, so the server's matching Sec-WebSocket-Protocol response frame
        // validates (the URLRequest+manual-header path fails handshake with -1011).
        let task = session.webSocketTask(with: url, protocols: subprotocols)
        // Default 1 MiB limit causes receive() to throw -1103 on large topic frames
        // (camera images, point clouds, URDF). Match Foxglove's 64 MiB budget.
        task.maximumMessageSize = 64 * 1024 * 1024
        task.resume()
        return URLSessionWebSocketChannel(task: task, session: session)
    }
}

/// Wraps one `URLSessionWebSocketTask` as a ``WebSocketChannel``.
final class URLSessionWebSocketChannel: WebSocketChannel, @unchecked Sendable {
    private let task: URLSessionWebSocketTask
    private let session: URLSession

    init(task: URLSessionWebSocketTask, session: URLSession) {
        self.task = task
        self.session = session
    }

    func send(_ frame: WebSocketFrame) async throws {
        switch frame {
        case let .text(string):
            try await task.send(.string(string))
        case let .binary(data):
            try await task.send(.data(data))
        }
    }

    func receive() async throws -> WebSocketFrame {
        let message = try await task.receive()
        switch message {
        case let .string(string):
            return .text(string)
        case let .data(data):
            return .binary(data)
        @unknown default:
            throw TransportError.protocolViolation("unknown WebSocket message kind")
        }
    }

    func close() async {
        task.cancel(with: .goingAway, reason: nil)
        session.invalidateAndCancel()
    }
}
