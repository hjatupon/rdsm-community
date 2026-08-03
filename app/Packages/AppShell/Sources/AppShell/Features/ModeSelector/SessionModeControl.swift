import SwiftUI

struct SessionModeControl: View {
    let currentMode: SessionMode
    let onSwitch: (SessionMode) -> Void
    let onShowModePicker: (() -> Void)?

    var body: some View {
        Menu {
            ForEach(SessionMode.allCases) { mode in
                Button {
                    onSwitch(mode)
                } label: {
                    HStack {
                        Image(systemName: mode.symbolName)
                            .foregroundStyle(mode.tint)
                        Text(mode.rawValue)
                        if mode == currentMode {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }

            if let onShowModePicker {
                Divider()
                Button {
                    onShowModePicker()
                } label: {
                    Label("Choose Mode…", systemImage: "arrow.triangle.branch")
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: currentMode.symbolName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(currentMode.tint)
                Text(currentMode.rawValue)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 7))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel("Session mode: \(currentMode.rawValue)")
        .accessibilityHint("Switch between Live Robot and Rosbag Replay modes.")
    }
}
