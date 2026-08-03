import SwiftUI
import TFTree
import MetalCore

// MARK: - Viewport mode seam (open-core)

/// Inputs the TF Universe viewport mode needs. All Core types (TFTree, MetalContext),
/// so this file stays free of the Pro TFUniverse package.
@MainActor
public struct TFUniverseContext {
    public let tfTree: TFTree
    public let metalContext: MetalContext
    public let fixedFrame: String
    public let onExit: () -> Void

    public init(tfTree: TFTree, metalContext: MetalContext, fixedFrame: String, onExit: @escaping () -> Void) {
        self.tfTree = tfTree
        self.metalContext = metalContext
        self.fixedFrame = fixedFrame
        self.onExit = onExit
    }
}

/// Registry for alternate 3D-viewport modes contributed by paid packages.
/// The free build registers nothing, so the "TF Universe" mode toggle is absent and
/// the viewport shows the Scene only. The paid TFUniverse package registers the
/// immersive TF visualization at launch.
@MainActor
public final class ViewportModeRegistry {
    public static let shared = ViewportModeRegistry()
    private init() {}

    private var tfUniverseBuilder: (@MainActor (TFUniverseContext) -> AnyView)?

    public func registerTFUniverse(_ build: @escaping @MainActor (TFUniverseContext) -> AnyView) {
        tfUniverseBuilder = build
    }

    public var isTFUniverseAvailable: Bool { tfUniverseBuilder != nil }

    public func makeTFUniverse(_ context: TFUniverseContext) -> AnyView? {
        tfUniverseBuilder?(context)
    }
}
