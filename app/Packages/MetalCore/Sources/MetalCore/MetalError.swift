import Foundation

/// Errors surfaced by the MetalCore layer. The public API throws only these — no
/// raw Metal `NSError`s escape (mirrors the Transport integration contract).
public enum MetalError: Error, Sendable, Equatable {
    /// No Metal device is available (headless CI, or a Mac without a GPU).
    case noDevice
    /// `MTLDevice.makeBuffer` returned nil for the requested length.
    case bufferAllocationFailed(length: Int)
    /// A shader library named `X` could not be found in the given bundle.
    case libraryNotFound(String)
    /// The Metal compiler rejected a shader source/library.
    case shaderCompilationFailed(String)
}
