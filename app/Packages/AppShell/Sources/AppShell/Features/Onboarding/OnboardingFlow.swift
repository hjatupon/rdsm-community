import SwiftUI

/// Two-screen welcome wizard shown on first launch.
/// Dismissed into MainWindow; sets `hasSeenOnboarding` in UserDefaults on completion.
struct OnboardingFlow: View {
    @Binding var isPresented: Bool
    @State private var page: Int = 0

    private let pageCount = 2

    var body: some View {
        ZStack {
            Color(.windowBackgroundColor).ignoresSafeArea()

            switch page {
            case 0:  WelcomePage  { advanceToPage1() }
            default: ConnectPage  { finish() }
            }

            // Step dots — bottom overlay
            VStack {
                Spacer()
                HStack(spacing: 6) {
                    ForEach(0..<pageCount, id: \.self) { index in
                        Circle()
                            .fill(index == page ? Color.ros2Accent : Color.secondary.opacity(0.4))
                            .frame(width: 7, height: 7)
                    }
                }
                .padding(.bottom, 16)
            }
        }
        .frame(width: 560, height: 440)
    }

    // MARK: - Actions

    private func advanceToPage1() {
        UserDefaults.standard.set(true, forKey: "hasSeenOnboarding")
        page = 1
    }

    private func finish() {
        UserDefaults.standard.set(true, forKey: "hasSeenOnboarding")
        withAnimation { isPresented = false }
    }
}

// MARK: - Page 1: Welcome

private struct WelcomePage: View {
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "cube.transparent.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
                .symbolEffect(.pulse)

            VStack(spacing: 8) {
                Text("Welcome to ROS2 Studio")
                    .font(.largeTitle.bold())
                Text("Your Mac is the beautiful cockpit.\nYour Linux machine runs the robot.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Button("Get Started") { onNext() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .accessibilityLabel("Get Started")
                .accessibilityHint("Continue to the next onboarding step.")

            Spacer().frame(height: 8)
        }
        .padding(40)
    }
}

// MARK: - Page 2: Connection setup hint

private struct ConnectPage: View {
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)

            VStack(spacing: 10) {
                Text("Connect Your Robot")
                    .font(.title2.bold())

                Text("Click the connection menu in the toolbar and choose **New Connection…** to connect your robot running **rosbridge_suite** on port 9090.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }

            Spacer()

            Button("Open ROS2 Studio") { onDone() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)

            Spacer().frame(height: 8)
        }
        .padding(40)
    }
}
