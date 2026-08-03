import Metal

/// A small fluent builder for `MTLRenderPassDescriptor`s, so renderers describe
/// their attachments declaratively instead of mutating a descriptor in place.
///
/// ```swift
/// let pass = RenderPassBuilder()
///     .colorAttachment(drawable, clear: .init(red: 0.05, green: 0.05, blue: 0.07, alpha: 1),
///                      load: .clear, store: .store)
///     .depthAttachment(depthTexture, clear: 1.0)
///     .build()
/// ```
public struct RenderPassBuilder {
    private struct ColorAttachment {
        let texture: MTLTexture
        let clear: MTLClearColor
        let load: MTLLoadAction
        let store: MTLStoreAction
    }

    private var colorAttachments: [ColorAttachment] = []
    private var depth: (texture: MTLTexture, clear: Double)?

    public init() {}

    /// Appends a color attachment. Multiple calls add successive color slots.
    public func colorAttachment(
        _ texture: MTLTexture,
        clear: MTLClearColor,
        load: MTLLoadAction,
        store: MTLStoreAction) -> RenderPassBuilder
    {
        var copy = self
        copy.colorAttachments.append(ColorAttachment(texture: texture, clear: clear, load: load, store: store))
        return copy
    }

    /// Sets the depth attachment (cleared to `clear`, then discarded).
    public func depthAttachment(_ texture: MTLTexture, clear: Double) -> RenderPassBuilder {
        var copy = self
        copy.depth = (texture, clear)
        return copy
    }

    /// Materializes the configured `MTLRenderPassDescriptor`.
    public func build() -> MTLRenderPassDescriptor {
        let descriptor = MTLRenderPassDescriptor()
        for (index, attachment) in colorAttachments.enumerated() {
            let slot = descriptor.colorAttachments[index]
            slot?.texture = attachment.texture
            slot?.clearColor = attachment.clear
            slot?.loadAction = attachment.load
            slot?.storeAction = attachment.store
        }
        if let depth {
            descriptor.depthAttachment.texture = depth.texture
            descriptor.depthAttachment.clearDepth = depth.clear
            descriptor.depthAttachment.loadAction = .clear
            descriptor.depthAttachment.storeAction = .dontCare
        }
        return descriptor
    }
}
