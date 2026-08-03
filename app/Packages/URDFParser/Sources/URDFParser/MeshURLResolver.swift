import Foundation

/// Resolves `package://` URIs found in URDF `<mesh filename="..."/>` elements
/// into absolute file system URLs using a caller-supplied package-path map.
///
/// URIs that are already absolute (`file://` or starting with `/`) are returned
/// unchanged. Relative URIs are resolved relative to `baseURL`.
///
/// Example:
/// ```swift
/// let resolver = MeshURLResolver(packagePaths: ["my_robot": URL(fileURLWithPath: "/opt/ros/my_robot")])
/// let url = resolver.resolve("package://my_robot/meshes/base.dae")
/// // → URL(fileURLWithPath: "/opt/ros/my_robot/meshes/base.dae")
/// ```
public struct MeshURLResolver: Sendable {
    private let packagePaths: [String: URL]
    private let baseURL: URL?

    public init(packagePaths: [String: URL] = [:], baseURL: URL? = nil) {
        self.packagePaths = packagePaths
        self.baseURL = baseURL
    }

    /// Resolves a mesh filename string from a URDF into an absolute URL.
    /// Returns `nil` if the URI uses an unknown package name.
    public func resolve(_ filename: String) -> URL? {
        if filename.hasPrefix("package://") {
            return resolvePackageURI(filename)
        } else if filename.hasPrefix("file://") {
            return URL(string: filename)
        } else if filename.hasPrefix("/") {
            return URL(fileURLWithPath: filename)
        } else if let base = baseURL {
            return base.appendingPathComponent(filename)
        }
        return URL(fileURLWithPath: filename)
    }

    private func resolvePackageURI(_ uri: String) -> URL? {
        // package://<packageName>/<rest>
        let withoutScheme = uri.dropFirst("package://".count)
        guard let slashIdx = withoutScheme.firstIndex(of: "/") else { return nil }
        let packageName = String(withoutScheme[..<slashIdx])
        let relativePath = String(withoutScheme[slashIdx...].dropFirst()) // drop leading /
        guard let packageRoot = packagePaths[packageName] else { return nil }
        return packageRoot.appendingPathComponent(relativePath)
    }
}
