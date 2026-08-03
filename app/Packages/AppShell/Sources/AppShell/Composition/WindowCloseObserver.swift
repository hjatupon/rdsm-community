import AppKit
import SwiftUI

/// Attaches a close notification observer to the specific NSWindow that contains
/// this view. Fires `onClose` only when THIS window closes — not other windows
/// (e.g., the Settings window). Uses viewDidMoveToWindow for reliable registration.
struct WindowCloseObserver: NSViewRepresentable {
    let onClose: @MainActor () -> Void

    func makeNSView(context: Context) -> WindowObserverNSView {
        let view = WindowObserverNSView()
        view.onClose = onClose
        return view
    }

    func updateNSView(_ nsView: WindowObserverNSView, context: Context) {
        nsView.onClose = onClose
    }
}

/// Custom NSView subclass that registers a close observer when it enters a window.
/// `viewDidMoveToWindow` is the reliable hook — called once the view has a real window.
final class WindowObserverNSView: NSView {
    var onClose: (@MainActor () -> Void)?
    private var closeObserver: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Clear previous observer (view may move windows during lifecycle)
        if let obs = closeObserver { NotificationCenter.default.removeObserver(obs) }
        closeObserver = nil

        guard let window = self.window else { return }
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,   // only THIS specific window — not Settings or other windows
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.onClose?()
            }
        }
    }
}
