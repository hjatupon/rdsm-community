import Foundation
@preconcurrency import Metal
import ModelIO
import MetalKit

/// A mesh fully loaded into GPU-accessible Metal buffers.
///
/// Each submesh corresponds to one material group in the source file.
/// Vertex data is interleaved: position (float3), normal (float3), texcoord (float2) — 32 bytes/vertex.
///
/// ``LoadedMesh`` is a value type that owns its ``MTLBuffer`` references via reference counting.
/// Releasing the last ``LoadedMesh`` copy returns the buffers to the GPU heap.
public struct LoadedMesh: Sendable, Equatable {
    /// Interleaved vertex buffer: [position: float3, normal: float3, texcoord: float2].
    public let vertexBuffer: MTLBuffer
    /// Total number of vertices across all submeshes.
    public let vertexCount: Int
    /// One entry per material group in the source file.
    public let submeshes: [Submesh]
    /// Axis-aligned bounding box in model space.
    public let boundingBox: BoundingBox
    /// Source file URL, for caching and debug display.
    public let sourceURL: URL

    /// One material group with its own index buffer and surface properties.
    public struct Submesh: Sendable, Equatable {
        public let indexBuffer: MTLBuffer
        public let indexCount: Int
        public let indexType: MTLIndexType
        public let material: Material
        public let primitiveType: MTLPrimitiveType

        public static func == (lhs: Submesh, rhs: Submesh) -> Bool {
            lhs.indexBuffer === rhs.indexBuffer &&
            lhs.indexCount == rhs.indexCount &&
            lhs.indexType == rhs.indexType &&
            lhs.material == rhs.material &&
            lhs.primitiveType == rhs.primitiveType
        }
    }

    /// Axis-aligned bounding box expressed in model-space coordinates.
    public struct BoundingBox: Sendable, Equatable {
        public let min: SIMD3<Float>
        public let max: SIMD3<Float>

        public var center: SIMD3<Float> { (min + max) * 0.5 }
        public var size: SIMD3<Float> { max - min }
        public var diagonal: Float { simd_length(size) }
    }

    public static func == (lhs: LoadedMesh, rhs: LoadedMesh) -> Bool {
        lhs.vertexBuffer === rhs.vertexBuffer &&
        lhs.vertexCount == rhs.vertexCount &&
        lhs.submeshes == rhs.submeshes &&
        lhs.boundingBox == rhs.boundingBox &&
        lhs.sourceURL == rhs.sourceURL
    }
}

/// Surface material properties extracted from the source file.
///
/// Textures are not loaded in 0.1.0 — only flat colour values are captured.
public struct Material: Sendable, Equatable {
    public let name: String
    public let baseColor: SIMD4<Float>
    public let metallic: Float
    public let roughness: Float

    public static let `default` = Material(
        name: "default",
        baseColor: SIMD4(0.8, 0.8, 0.8, 1.0),
        metallic: 0.0,
        roughness: 0.8)

    public init(name: String, baseColor: SIMD4<Float>, metallic: Float, roughness: Float) {
        self.name = name
        self.baseColor = baseColor
        self.metallic = metallic
        self.roughness = roughness
    }
}
