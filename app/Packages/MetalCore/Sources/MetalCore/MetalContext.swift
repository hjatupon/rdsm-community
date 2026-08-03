import Foundation
import Logging
import Metal

/// The single GPU entry point for the whole app: one `MTLDevice` and one
/// `MTLCommandQueue`, shared across every renderer (Contract C4 — one
/// `MetalContext` per app, created in the composition root).
///
/// `@unchecked Sendable`: the wrapped Metal objects are thread-safe for the uses
/// here (the device and queue are themselves safe to share; encoders are created
/// per-thread by callers and are never shared).
public final class MetalContext: @unchecked Sendable {
    public let device: MTLDevice
    public let commandQueue: MTLCommandQueue
    private let logger: any LoggerProtocol

    /// Creates the system-default device and a command queue.
    /// - Throws: ``MetalError/noDevice`` when no GPU is present (headless CI).
    public convenience init() throws {
        try self.init(logger: Logger(subsystem: "studio.ros2", category: "metalcore"))
    }

    init(logger: any LoggerProtocol) throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            logger.error("no Metal device available")
            throw MetalError.noDevice
        }
        guard let queue = device.makeCommandQueue() else {
            logger.error("failed to create command queue")
            throw MetalError.noDevice
        }
        self.device = device
        commandQueue = queue
        self.logger = logger
        logger.info("metal context ready", fields: [LogField(key: "device", value: device.name)])
    }

    /// Allocates a fresh `MTLBuffer`.
    /// - Throws: ``MetalError/bufferAllocationFailed(length:)`` if allocation fails.
    public func makeBuffer(length: Int, options: MTLResourceOptions) throws -> MTLBuffer {
        guard length > 0, let buffer = device.makeBuffer(length: length, options: options) else {
            throw MetalError.bufferAllocationFailed(length: length)
        }
        return buffer
    }

    /// Loads a precompiled `.metallib` shader library from `bundle`.
    /// - Throws: ``MetalError/libraryNotFound(_:)`` if the `.metallib` is absent,
    ///   ``MetalError/shaderCompilationFailed(_:)`` if Metal rejects it.
    public func loadShaderLibrary(named: String, bundle: Bundle) throws -> MTLLibrary {
        guard let url = bundle.url(forResource: named, withExtension: "metallib") else {
            throw MetalError.libraryNotFound(named)
        }
        do {
            return try device.makeLibrary(URL: url)
        } catch {
            throw MetalError.shaderCompilationFailed(error.localizedDescription)
        }
    }
}
