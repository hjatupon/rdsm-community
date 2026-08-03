import Foundation

/// Static registry for file URLs that need to be loaded by the ViewModel.
/// File picker callbacks store URLs here; the ViewModel reads them when layers change.
public final class FileLoadRegistry: @unchecked Sendable {
    public static let shared = FileLoadRegistry()
    private let lock = NSLock()
    private var pendingStaticMaps: [UUID: (yaml: URL, pgm: URL)] = [:]
    private var pendingMeshMaps: [UUID: URL] = [:]

    private init() {}

    public func registerStaticMap(layerID: UUID, yamlURL: URL, pgmURL: URL) {
        lock.withLock { pendingStaticMaps[layerID] = (yamlURL, pgmURL) }
    }

    public func registerMeshMap(layerID: UUID, fileURL: URL) {
        lock.withLock { pendingMeshMaps[layerID] = fileURL }
    }

    public func takeStaticMap(layerID: UUID) -> (yaml: URL, pgm: URL)? {
        lock.withLock { pendingStaticMaps.removeValue(forKey: layerID) }
    }

    public func takeMeshMap(layerID: UUID) -> URL? {
        lock.withLock { pendingMeshMaps.removeValue(forKey: layerID) }
    }
}
