import SwiftUI

struct ModeSelectorView: View {
    @Binding var isPresented: Bool
    let onSelect: (SessionMode) -> Void

    @State private var selectedMode: SessionMode?

    var body: some View {
        VStack(spacing: 0) {
            header
            modeCards
            Spacer()
            footer
        }
        .frame(width: 560, height: 480)
        .background(Color(.windowBackgroundColor))
    }

    private var header: some View {
        VStack(spacing: 6) {
            Image(systemName: "cube.transparent.fill")
                .font(.system(size: 40))
                .foregroundStyle(Color.ros2Accent)
                .symbolEffect(.pulse)
                .padding(.top, 32)

            Text(AppInfo.displayName)
                .font(.title.bold())

            Text("Your Mac is the beautiful cockpit.\nChoose your session mode to get started.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
        }
    }

    private var modeCards: some View {
        HStack(spacing: 20) {
            modeCard(mode: .live)
            modeCard(mode: .replay)
        }
        .padding(.horizontal, 40)
        .padding(.top, 28)
    }

    private func modeCard(mode: SessionMode) -> some View {
        let isSelected = selectedMode == mode
        return Button {
            selectedMode = mode
        } label: {
            VStack(spacing: 14) {
                Image(systemName: mode.symbolName)
                    .font(.system(size: 36))
                    .foregroundStyle(mode.tint)
                    .padding(.top, 20)

                Text(mode.rawValue)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(mode.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)

                Text(mode.capabilitiesDescription)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 8)

                Spacer(minLength: 0)

                if isSelected {
                    Text("Selected")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(mode.tint)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(mode.tint.opacity(0.12), in: Capsule())
                        .padding(.bottom, 16)
                } else {
                    Text("Select")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 16)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? mode.tint : Color.gray.opacity(0.3), lineWidth: isSelected ? 2 : 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(mode.rawValue) mode")
        .accessibilityHint(mode.description)
    }

    private var footer: some View {
        VStack(spacing: 12) {
            Button {
                if let mode = selectedMode {
                    onSelect(mode)
                    isPresented = false
                }
            } label: {
                Text("Continue")
                    .frame(maxWidth: 240)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(selectedMode == nil)
            .keyboardShortcut(.defaultAction)
            .padding(.bottom, 24)
        }
    }
}
