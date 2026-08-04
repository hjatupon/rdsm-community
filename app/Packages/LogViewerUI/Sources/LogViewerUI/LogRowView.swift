import SwiftUI
import LogStore

struct LogRowView: View {
    let entry: LogEntry
    let index: Int
    let isExpanded: Bool
    let fontSize: Int
    let wrapLines: Bool
    var onToggleExpand: (() -> Void)?
    var onCopy: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            mainRow
            if isExpanded {
                expandedDetails
                    .padding(.leading, 100)
                    .padding(.bottom, 4)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(index % 2 == 0 ? Color.clear : Color.white.opacity(0.02))
    }

    @ViewBuilder
    private var mainRow: some View {
        HStack(alignment: .top, spacing: 6) {
            // Expand toggle
            Button {
                onToggleExpand?()
            } label: {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
                    .frame(width: 10)
            }
            .buttonStyle(.plain)
            .help("Show details")

            // Timestamp
            Text(timeString(from: entry.timestampNs))
                .font(.system(size: CGFloat(fontSize)).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 92, alignment: .leading)

            // Severity badge
            Text(entry.severity.label)
                .font(.system(size: CGFloat(fontSize - 1)).monospaced().bold())
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(severityColor(entry.severity).opacity(0.25),
                            in: RoundedRectangle(cornerRadius: 3))
                .foregroundStyle(severityColor(entry.severity))

            // Node name
            Text(entry.node)
                .font(.system(size: CGFloat(fontSize)).monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 130, alignment: .leading)
                .foregroundStyle(.primary)

            // Message
            Text(entry.message)
                .font(.system(size: CGFloat(fontSize)).monospaced())
                .lineLimit(wrapLines ? nil : 2)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var expandedDetails: some View {
        HStack(spacing: 12) {
            if !entry.file.isEmpty {
                HStack(spacing: 3) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                    Text("\(entry.file):\(entry.line)")
                        .font(.system(size: CGFloat(fontSize - 1)).monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            if !entry.function.isEmpty {
                HStack(spacing: 3) {
                    Image(systemName: "f.square")
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                    Text(entry.function)
                        .font(.system(size: CGFloat(fontSize - 1)).monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Copy full entry
            Button {
                onCopy?()
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("Copy entry details")
        }
    }

    private func severityColor(_ s: LogSeverity) -> Color {
        switch s {
        case .debug: return .gray
        case .info:  return .blue
        case .warn:  return .orange
        case .error: return .red
        case .fatal: return .purple
        }
    }

}

#if canImport(AppKit)
import AppKit

private struct CursorOnHover: ViewModifier {
    func body(content: Content) -> some View {
        content.onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

extension View {
    func cursorOnHover() -> some View {
        modifier(CursorOnHover())
    }
}
#else
extension View {
    func cursorOnHover() -> some View { self }
}
#endif
