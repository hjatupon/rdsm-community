import Foundation

/// All errors thrown by ``MeshLoader``.
public enum MeshLoaderError: Error, Sendable, CustomStringConvertible {
    /// The file extension is not in the supported set (stl, obj, dae).
    case unsupportedFormat(String)
    /// The file could not be read or does not exist.
    case fileNotFound(URL)
    /// ModelIO rejected the file (corrupt, truncated, or invalid geometry).
    case loadFailed(URL, String)
    /// The mesh contains no usable submeshes after loading.
    case emptyMesh(URL)

    public var description: String {
        switch self {
        case .unsupportedFormat(let ext):
            "MeshLoaderError: unsupported format '\(ext)' — supported: stl, obj, dae"
        case .fileNotFound(let url):
            "MeshLoaderError: file not found: \(url.path)"
        case .loadFailed(let url, let reason):
            "MeshLoaderError: failed to load \(url.lastPathComponent) — \(reason)"
        case .emptyMesh(let url):
            "MeshLoaderError: \(url.lastPathComponent) produced no geometry"
        }
    }
}
