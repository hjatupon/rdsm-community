import Foundation

/// The saved state of a single UI panel.
///
/// `configuration` is a raw JSON blob owned and decoded by the panel type that
/// created it — LayoutEngine never inspects it. This keeps LayoutEngine decoupled
/// from every UI module (integration contract C6).
public struct PanelState: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    /// Stable type discriminator, e.g. `"topicBrowser"`, `"viewer3d"`, `"inspector"`.
    public let panelType: String
    public var frame: LayoutRect
    public var isVisible: Bool
    /// Opaque JSON blob — encoded/decoded by the owning UI module.
    public var configuration: Data

    public init(
        id: UUID = UUID(),
        panelType: String,
        frame: LayoutRect,
        isVisible: Bool = true,
        configuration: Data = Data()
    ) {
        self.id = id
        self.panelType = panelType
        self.frame = frame
        self.isVisible = isVisible
        self.configuration = configuration
    }
}
