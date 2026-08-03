import Foundation
import SwiftUI
import Combine

/// Toast severity levels — control color and default dismiss timing.
public enum ToastKind: Sendable {
    case info, success, warning, error
}

struct Toast: Identifiable, Sendable {
    let id = UUID()
    let kind: ToastKind
    let title: String
    let message: String?
    let autoDismiss: TimeInterval
}

/// Global in-window notification center. Mount once at the root of MainWindow.
@MainActor
public final class ToastCenter: ObservableObject {
    public static let shared = ToastCenter()

    @Published private(set) var toasts: [Toast] = []
    private var dismissTasks: [UUID: Task<Void, Never>] = [:]
    private let maxStacked = 3

    public func show(_ kind: ToastKind, title: String, message: String? = nil, autoDismiss: TimeInterval? = nil) {
        let duration = autoDismiss ?? (kind == .error ? 8.0 : 4.0)
        let toast = Toast(kind: kind, title: title, message: message, autoDismiss: duration)
        if toasts.count >= maxStacked, let first = toasts.first {
            dismiss(first.id)
        }
        toasts.append(toast)
        let id = toast.id
        let task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.dismiss(id) }
        }
        dismissTasks[id] = task
    }

    func dismiss(_ id: UUID) {
        toasts.removeAll { $0.id == id }
        dismissTasks[id]?.cancel()
        dismissTasks[id] = nil
    }
}

struct ToastStack: View {
    @ObservedObject var center: ToastCenter

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            ForEach(center.toasts) { toast in
                ToastView(toast: toast, onDismiss: { center.dismiss(toast.id) })
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .padding(16)
        .frame(maxWidth: 360, alignment: .trailing)
        .animation(.easeInOut(duration: 0.22), value: center.toasts.map { $0.id })
    }
}

private struct ToastView: View {
    let toast: Toast
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
                .font(.system(size: 16, weight: .semibold))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(toast.title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)
                if let message = toast.message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss notification")
        }
        .padding(12)
        .frame(maxWidth: 340, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(iconColor.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(kindLabel): \(toast.title)\(toast.message.map { ". " + $0 } ?? "")")
        .accessibilityAddTraits(.updatesFrequently)
    }

    private var iconName: String {
        switch toast.kind {
        case .info: return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }

    private var iconColor: Color {
        switch toast.kind {
        case .info: return .blue
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }

    private var kindLabel: String {
        switch toast.kind {
        case .info: return "Info"
        case .success: return "Success"
        case .warning: return "Warning"
        case .error: return "Error"
        }
    }
}
