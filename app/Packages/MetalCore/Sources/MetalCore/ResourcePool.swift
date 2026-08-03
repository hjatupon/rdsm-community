import Foundation
import Logging
import Metal

/// A reuse pool for `MTLBuffer`s, keyed by power-of-two size bucket. Renderers
/// that churn per-frame buffers (point clouds, charts) acquire here instead of
/// allocating fresh GPU memory every frame, keeping the buffer-cycle budget low.
///
/// `@unchecked Sendable`: all mutable state is guarded by `lock`.
public final class ResourcePool: @unchecked Sendable {
    private let context: MetalContext
    private let logger: any LoggerProtocol
    private let lock = NSLock()
    /// Free buffers keyed by their power-of-two bucket length.
    private var freeList: [Int: [MTLBuffer]] = [:]

    public init(context: MetalContext) {
        self.context = context
        logger = Logger(subsystem: "studio.ros2", category: "metalcore.pool")
    }

    init(context: MetalContext, logger: any LoggerProtocol) {
        self.context = context
        self.logger = logger
    }

    /// Returns a buffer of at least `length` bytes, reusing a pooled one when a
    /// bucket match exists, otherwise allocating a fresh bucket-sized buffer.
    public func acquireBuffer(length: Int, options: MTLResourceOptions) -> MTLBuffer {
        let bucket = Self.bucket(for: length)
        let pooled: MTLBuffer? = lock.withLock {
            guard var bufs = freeList[bucket], !bufs.isEmpty else { return nil }
            let buf = bufs.removeLast()
            freeList[bucket] = bufs
            return buf
        }
        if let pooled {
            logger.debug("pool hit", fields: [LogField(key: "bucket", value: String(bucket))])
            return pooled
        }
        logger.debug("pool miss", fields: [LogField(key: "bucket", value: String(bucket))])
        // Allocate at the bucket size so the buffer is reusable for the whole bucket.
        // The API is non-throwing; a failure here is an unrecoverable GPU OOM.
        guard let buffer = context.device.makeBuffer(length: bucket, options: options) else {
            preconditionFailure("ResourcePool: GPU buffer allocation failed for \(bucket) bytes")
        }
        return buffer
    }

    /// Returns a buffer to its bucket for later reuse. Buckets are capped at 4
    /// entries so GPU memory doesn't accumulate across varying point-cloud sizes.
    public func release(_ buffer: MTLBuffer) {
        let bucket = Self.bucket(for: buffer.length)
        lock.withLock {
            if freeList[bucket, default: []].count < 4 {
                freeList[bucket, default: []].append(buffer)
            }
            // else: drop the buffer — ARC releases the MTLBuffer back to the GPU allocator.
        }
    }

    /// Rounds `length` up to the next power of two (minimum 1), so buffers of
    /// similar size share a bucket and can be reused interchangeably.
    static func bucket(for length: Int) -> Int {
        guard length > 1 else { return 1 }
        return 1 << (Int.bitWidth - (length - 1).leadingZeroBitCount)
    }
}
