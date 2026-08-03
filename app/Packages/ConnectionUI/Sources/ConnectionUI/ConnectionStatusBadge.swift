import SwiftUI
import Transport
import ConnectionManager

/// A compact status pill showing the live state of one connection handle.
///
/// Observes `handle.transport.state` via a `Task` and updates on the main actor.
public struct ConnectionStatusBadge: View {
    public let handle: ConnectionHandle

    @State private var state: TransportState = .disconnected
    @State private var watchTask: Task<Void, Never>? = nil

    public init(handle: ConnectionHandle) {
        self.handle = handle
    }

    public var body: some View {
        Label(label, systemImage: icon)
            .font(.caption.weight(.medium))
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
            .help("Connection status: \(label)")
            .task {
                watchTask?.cancel()
                watchTask = Task {
                    // Seed with current state first — AsyncStream doesn't replay past events,
                    // so a badge created after connect would otherwise stay ".disconnected" forever.
                    let current = await handle.transport.currentState()
                    await MainActor.run { state = current }
                    for await s in handle.transport.state {
                        await MainActor.run { state = s }
                    }
                }
            }
            .onDisappear { watchTask?.cancel() }
    }

    // MARK: - Private helpers

    private var label: String {
        switch state {
        case .disconnected:         return "Disconnected"
        case .connecting:           return "Connecting…"
        case .connected:            return "Connected"
        case .reconnecting(let n):  return "Reconnecting (\(n))"
        case .failed:               return "Failed"
        }
    }

    private var icon: String {
        switch state {
        case .disconnected:   return "circle"
        case .connecting:     return "arrow.trianglehead.clockwise"
        case .connected:      return "circle.fill"
        case .reconnecting:   return "arrow.trianglehead.clockwise"
        case .failed:         return "exclamationmark.circle.fill"
        }
    }

    private var color: Color {
        switch state {
        case .disconnected:  return .secondary
        case .connecting:    return .orange
        case .connected:     return .green
        case .reconnecting:  return .orange
        case .failed:        return .red
        }
    }
}
