import Foundation
import SwiftUI
import Transport

// MARK: - Layer Type

/// Every renderable ROS message type the 3D viewer supports.
public enum LayerType: String, Codable, Sendable, CaseIterable {
    case laserScan       = "sensor_msgs/msg/LaserScan"
    case pointCloud2     = "sensor_msgs/msg/PointCloud2"
    case occupancyGrid   = "nav_msgs/msg/OccupancyGrid"
    case octomap         = "octomap_msgs/Octomap"
    case image           = "sensor_msgs/msg/Image"
    case compressedImage = "sensor_msgs/msg/CompressedImage"
    case odometry        = "nav_msgs/msg/Odometry"
    case markerArray     = "visualization_msgs/msg/MarkerArray"
    case poseStamped     = "geometry_msgs/msg/PoseStamped"
    case path            = "nav_msgs/msg/Path"
    case tfFrames        = "__builtin__/TFFrames"
    case robotModel      = "__builtin__/RobotModel"
    case staticMap       = "__file__/StaticMap"
    case meshMap         = "__file__/MeshMap"

    public var displayName: String {
        switch self {
        case .laserScan:       return "LaserScan"
        case .pointCloud2:     return "PointCloud2"
        case .occupancyGrid:   return "OccupancyGrid"
        case .octomap:         return "Octomap"
        case .image:           return "Image"
        case .compressedImage: return "CompressedImage"
        case .odometry:        return "Odometry"
        case .markerArray:     return "MarkerArray"
        case .poseStamped:     return "PoseStamped"
        case .path:            return "Nav Path"
        case .tfFrames:        return "TF Frames"
        case .robotModel:      return "Robot Model"
        case .staticMap:       return "Static Map"
        case .meshMap:         return "Mesh Map"
        }
    }

    public var systemImage: String {
        switch self {
        case .laserScan:                return "dot.radiowaves.forward"
        case .pointCloud2:              return "cube.fill"
        case .occupancyGrid:            return "map.fill"
        case .octomap:                  return "cube.transparent"
        case .image, .compressedImage:  return "photo"
        case .odometry:                 return "arrow.triangle.2.circlepath"
        case .markerArray:              return "cylinder.fill"
        case .poseStamped:              return "location.north.fill"
        case .path:                     return "arrow.triangle.pull"
        case .tfFrames:                 return "move.3d"
        case .robotModel:               return "figure.stand"
        case .staticMap:                return "map"
        case .meshMap:                  return "square.and.arrow.up"
        }
    }

    /// Infer layer type from a ROS schema name.
    public static func detect(from schemaName: String) -> LayerType? {
        allCases.first { $0 != .tfFrames && $0 != .robotModel && $0 != .staticMap && $0 != .meshMap && $0.rawValue == schemaName }
    }

    /// True when the type feeds into the Metal point-cloud renderer (vs. other overlays).
    public var isPointBased: Bool {
        switch self {
        case .laserScan, .pointCloud2, .occupancyGrid, .octomap,
             .odometry, .markerArray, .poseStamped, .path, .tfFrames:  return true
        case .image, .compressedImage, .robotModel, .staticMap, .meshMap:  return false
        }
    }

    /// True for synthetic (non-topic) built-in layers (TF Frames, Robot Model).
    public var isBuiltIn: Bool {
        switch self {
        case .tfFrames, .robotModel: return true
        default:                     return false
        }
    }

    /// True for file-based layers (Static Map, Mesh Map).
    public var isFileBased: Bool {
        switch self {
        case .staticMap, .meshMap: return true
        default:                   return false
        }
    }
}

// MARK: - Layer Color Mode

/// How a LaserScan (or other range-based) layer assigns point colors.
public enum LayerColorMode: String, Codable, Sendable, CaseIterable {
    /// All points use the layer's flat `r/g/b` colour.
    case flat        = "flat"
    /// Points are coloured red→yellow→green by normalized distance.
    case byDistance  = "byDistance"
    /// Points are coloured by intensity channel (blue→cyan→green→yellow→red).
    case byIntensity = "byIntensity"

    public var displayName: String {
        switch self {
        case .flat:        return "Flat"
        case .byDistance:  return "By Distance"
        case .byIntensity: return "By Intensity"
        }
    }
}

// MARK: - LaserScan Viz Mode

/// How a LaserScan layer renders beams.
public enum ScanVizMode: String, Codable, Sendable, CaseIterable {
    case dots = "dots"
    case rays = "rays"

    public var displayName: String {
        switch self {
        case .dots: return "Dots"
        case .rays: return "Rays"
        }
    }
}

// MARK: - PointCloud2 Color Mode

/// How a PointCloud2 layer colors each point.
public enum PC2ColorMode: String, Codable, Sendable, CaseIterable {
    case flat        = "flat"
    case byHeight    = "byHeight"
    case byIntensity = "byIntensity"
    case byRGB       = "byRGB"

    public var displayName: String {
        switch self {
        case .flat:        return "Flat"
        case .byHeight:    return "By Height"
        case .byIntensity: return "By Intensity"
        case .byRGB:       return "By RGB"
        }
    }
}

// MARK: - Layer Settings

/// Per-layer display settings. Codable so they can be stored in ProfileStore later.
/// New fields MUST always use decodeIfPresent with a default so that old stored data
/// (missing the key) is silently upgraded rather than wiping the entire config.
public struct LayerSettings: Sendable, Equatable {
    // MARK: Common
    /// RGB colour, 0–1. Default: brand teal #2EB9B0.
    public var r: Double = 0.18
    public var g: Double = 0.726
    public var b: Double = 0.69
    /// Overall opacity, 0–1.
    public var opacity: Double = 1.0
    /// Point radius (scan/cloud layers), in Metal points.
    public var pointSize: Float = 3.0
    /// Seconds to keep old geometry before discarding (0 = latest frame only).
    public var decaySeconds: Double = 0

    // MARK: TF Frames
    /// Length of each TF axis arrow in meters (TF Frames layer only).
    public var axisLength: Double = 0.3
    /// Whether to show frame name labels in the 3D viewport (TF Frames layer only).
    public var showFrameNames: Bool = true
    /// Whether to draw parent→child connection lines between frames (TF Frames layer only).
    public var showFrameLinks: Bool = true
    /// Frame names to hide from the TF visualization (TF Frames layer only).
    public var hiddenFrames: Set<String> = []
    /// Age (seconds) below which a dynamic TF edge is considered "fresh" (full brightness).
    public var tfFreshThresholdSec: Double = 0.5
    /// Age (seconds) above which a dynamic TF edge is considered "stale" (heavily dimmed).
    public var tfStaleThresholdSec: Double = 2.0
    /// Connection line width multiplier (1.0 = default 10 points). Higher = thicker lines.
    public var linkLineWidth: Double = 1.0
    /// Connection line style: 0 = solid, 1 = dashed.
    public var linkLineStyle: Int = 0
    /// Connection line color RGB. Default: gray (0.5, 0.5, 0.5).
    public var linkLineR: Double = 0.5
    public var linkLineG: Double = 0.5
    public var linkLineB: Double = 0.5
    /// Axis line width multiplier (1.0 = default 40 points). Higher = thicker axis lines.
    public var axisLineWidth: Double = 1.0
    /// Per-axis visibility: show X axis (red).
    public var axisShowX: Bool = true
    /// Per-axis visibility: show Y axis (green).
    public var axisShowY: Bool = true
    /// Per-axis visibility: show Z axis (blue).
    public var axisShowZ: Bool = true
    /// Whether to show X/Y/Z axis labels at the tip of each axis.
    public var axisShowLabels: Bool = false
    /// Font size for axis labels (pt). Range: 8–24.
    public var axisLabelSize: Double = 10.0
    /// Size of the node marker at each frame origin (Metal points). Default: 6.0.
    public var frameNodeSize: Double = 6.0
    /// Node shape: 0 = dot, 1 = diamond, 2 = cross.
    public var frameNodeShape: Int = 0
    /// Frame color mode: 0 = standard RGB axes, 1 = by depth from root, 2 = static=teal / dynamic=orange.
    public var frameColorMode: Int = 0

    // MARK: LaserScan
    /// Color mode for LaserScan layers (flat vs by-distance gradient).
    public var colorMode: LayerColorMode = .flat
    /// Minimum range filter (meters). Beams closer than this are discarded.
    public var rangeMin: Double = 0.0
    /// Maximum range filter (meters). Beams farther than this are discarded.
    public var rangeMax: Double = 30.0
    /// Visualization mode: dots or rays from origin.
    public var scanVizMode: ScanVizMode = .dots

    // MARK: OccupancyGrid (map)
    /// Free cell color RGB (0–1). Default: near-white.
    public var freeR: Double = 0.94
    public var freeG: Double = 0.94
    public var freeB: Double = 0.94
    /// Unknown cell color RGB (0–1). Default: blue-gray.
    public var unknownR: Double = 0.55
    public var unknownG: Double = 0.65
    public var unknownB: Double = 0.75
    /// Whether to show cell-boundary grid lines on the map.
    public var showGridLines: Bool = false
    /// Whether to render unknown (-1) cells.
    public var showUnknownCells: Bool = true

    // MARK: PointCloud2
    /// How PointCloud2 points are colored.
    public var pc2ColorMode: PC2ColorMode = .flat
    /// Field name used for height coloring (default "z" = Metal Y after swizzle).
    public var pc2ColorFieldName: String = "z"
    /// Minimum height for the height gradient (meters, Metal Y-axis).
    public var pc2HeightMin: Double = -0.5
    /// Maximum height for the height gradient (meters, Metal Y-axis).
    public var pc2HeightMax: Double = 2.0
    /// Render every Nth point (1 = all, 2 = half, etc.).
    public var pc2StrideN: Int = 1

    // MARK: Odometry
    /// Whether to draw a breadcrumb trail behind the robot.
    public var showOdomTrail: Bool = true
    /// Maximum number of trail poses to keep.
    public var odomTrailLength: Int = 100
    /// Trail color RGB (0–1). Default: brand teal.
    public var odomTrailR: Double = 0.18
    public var odomTrailG: Double = 0.73
    public var odomTrailB: Double = 0.69
    /// Whether to render a short velocity arrow at the current pose.
    public var showVelocityArrow: Bool = false

    // MARK: Path
    /// Whether to render a large dot at every Nth waypoint.
    public var showPathWaypoints: Bool = true
    /// Render a waypoint marker every N poses.
    public var pathWaypointEveryN: Int = 5
    /// Point size for waypoint markers.
    public var pathWaypointSize: Double = 4.0

    // MARK: MarkerArray
    /// Namespace substring filter (empty = show all).
    public var markerNamespaceFilter: String = ""

    // MARK: Octomap
    /// Voxel size scale multiplier (1.0 = native resolution).
    public var octomapVoxelScale: Double = 1.0
    /// Maximum depth level to render (0 = root only, -1 = all levels).
    public var octomapMaxDepth: Int = -1
    /// Whether to render occupied voxels.
    public var octomapShowOccupied: Bool = true
    /// Whether to render free voxels.
    public var octomapShowFree: Bool = false
    /// Whether to render unknown voxels.
    public var octomapShowUnknown: Bool = false
    /// Occupied voxel color RGB (0–1).
    public var octomapOccupiedR: Double = 0.2
    public var octomapOccupiedG: Double = 0.6
    public var octomapOccupiedB: Double = 0.8
    /// Free voxel color RGB (0–1).
    public var octomapFreeR: Double = 0.8
    public var octomapFreeG: Double = 0.9
    public var octomapFreeB: Double = 1.0
    /// Voxel alpha (0–1).
    public var octomapAlpha: Double = 0.7
    /// LOD: render every Nth voxel (1 = all).
    public var octomapStrideN: Int = 1

    // MARK: Robot Model
    /// Multiplicative tint applied to every link's albedo color. Default: white (no tint).
    public var robotModelTintR: Double = 1.0
    public var robotModelTintG: Double = 1.0
    public var robotModelTintB: Double = 1.0
    /// Link names hidden from rendering (empty = all links shown).
    public var robotModelHiddenLinks: Set<String> = []
    /// Per-link mesh file overrides: linkName → absolute file path.
    public var robotModelMeshOverrides: [String: String] = [:]

    // MARK: Mesh Map
    /// Mesh color tint RGB (0–1). Default: near-white.
    public var meshMapR: Double = 0.9
    public var meshMapG: Double = 0.9
    public var meshMapB: Double = 0.9
    /// Whether to show wireframe overlay on mesh.
    public var meshMapShowWireframe: Bool = false
    /// Whether to render double-sided faces.
    public var meshMapDoubleSided: Bool = true
    /// Mesh LOD: render every Nth triangle (1 = all).
    public var meshMapStrideN: Int = 1

    public var swiftUIColor: Color {
        Color(red: r, green: g, blue: b, opacity: opacity)
    }

    public init() {}
}

// MARK: - LayerSettings Codable (manual — required for backward-compatible decoding)

extension LayerSettings: Codable {
    enum CodingKeys: String, CodingKey {
        case r, g, b, opacity, pointSize, decaySeconds
        case axisLength, showFrameNames, showFrameLinks, hiddenFrames
        case tfFreshThresholdSec, tfStaleThresholdSec
        case linkLineWidth, linkLineStyle, linkLineR, linkLineG, linkLineB
        case axisLineWidth, axisShowX, axisShowY, axisShowZ, axisShowLabels, axisLabelSize
        case frameNodeSize, frameNodeShape, frameColorMode
        case colorMode, rangeMin, rangeMax, scanVizMode
        case freeR, freeG, freeB
        case unknownR, unknownG, unknownB
        case showGridLines, showUnknownCells
        case pc2ColorMode, pc2ColorFieldName, pc2HeightMin, pc2HeightMax, pc2StrideN
        case showOdomTrail, odomTrailLength, odomTrailR, odomTrailG, odomTrailB, showVelocityArrow
        case showPathWaypoints, pathWaypointEveryN, pathWaypointSize
        case markerNamespaceFilter
        case octomapVoxelScale, octomapMaxDepth, octomapShowOccupied, octomapShowFree, octomapShowUnknown
        case octomapOccupiedR, octomapOccupiedG, octomapOccupiedB
        case octomapFreeR, octomapFreeG, octomapFreeB
        case octomapAlpha, octomapStrideN
        case robotModelTintR, robotModelTintG, robotModelTintB
        case robotModelHiddenLinks, robotModelMeshOverrides
        case meshMapR, meshMapG, meshMapB
        case meshMapShowWireframe, meshMapDoubleSided, meshMapStrideN
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Every field uses decodeIfPresent + default so that old stored JSON
        // (missing the key) silently upgrades without throwing keyNotFound.
        r            = try c.decodeIfPresent(Double.self, forKey: .r)            ?? 0.18
        g            = try c.decodeIfPresent(Double.self, forKey: .g)            ?? 0.726
        b            = try c.decodeIfPresent(Double.self, forKey: .b)            ?? 0.69
        opacity      = try c.decodeIfPresent(Double.self, forKey: .opacity)      ?? 1.0
        pointSize    = try c.decodeIfPresent(Float.self,  forKey: .pointSize)    ?? 3.0
        decaySeconds = try c.decodeIfPresent(Double.self, forKey: .decaySeconds) ?? 0
        // TF
        axisLength      = try c.decodeIfPresent(Double.self, forKey: .axisLength)      ?? 0.3
        showFrameNames  = try c.decodeIfPresent(Bool.self,   forKey: .showFrameNames)  ?? true
        showFrameLinks  = try c.decodeIfPresent(Bool.self,   forKey: .showFrameLinks)  ?? true
        hiddenFrames    = try c.decodeIfPresent(Set<String>.self, forKey: .hiddenFrames) ?? []
        tfFreshThresholdSec = try c.decodeIfPresent(Double.self, forKey: .tfFreshThresholdSec) ?? 0.5
        tfStaleThresholdSec = try c.decodeIfPresent(Double.self, forKey: .tfStaleThresholdSec) ?? 2.0
        linkLineWidth  = try c.decodeIfPresent(Double.self, forKey: .linkLineWidth)  ?? 1.0
        linkLineStyle  = try c.decodeIfPresent(Int.self,    forKey: .linkLineStyle)  ?? 0
        linkLineR      = try c.decodeIfPresent(Double.self, forKey: .linkLineR)      ?? 0.5
        linkLineG      = try c.decodeIfPresent(Double.self, forKey: .linkLineG)      ?? 0.5
        linkLineB      = try c.decodeIfPresent(Double.self, forKey: .linkLineB)      ?? 0.5
        axisLineWidth  = try c.decodeIfPresent(Double.self, forKey: .axisLineWidth)  ?? 1.0
        axisShowX      = try c.decodeIfPresent(Bool.self,   forKey: .axisShowX)      ?? true
        axisShowY      = try c.decodeIfPresent(Bool.self,   forKey: .axisShowY)      ?? true
        axisShowZ      = try c.decodeIfPresent(Bool.self,   forKey: .axisShowZ)      ?? true
        axisShowLabels = try c.decodeIfPresent(Bool.self,   forKey: .axisShowLabels) ?? false
        axisLabelSize  = try c.decodeIfPresent(Double.self, forKey: .axisLabelSize)  ?? 10.0
        frameNodeSize  = try c.decodeIfPresent(Double.self, forKey: .frameNodeSize)  ?? 6.0
        frameNodeShape = try c.decodeIfPresent(Int.self,    forKey: .frameNodeShape) ?? 0
        frameColorMode = try c.decodeIfPresent(Int.self,    forKey: .frameColorMode) ?? 0
        // LaserScan
        colorMode   = try c.decodeIfPresent(LayerColorMode.self, forKey: .colorMode)   ?? .flat
        rangeMin    = try c.decodeIfPresent(Double.self,          forKey: .rangeMin)    ?? 0.0
        rangeMax    = try c.decodeIfPresent(Double.self,          forKey: .rangeMax)    ?? 30.0
        scanVizMode = try c.decodeIfPresent(ScanVizMode.self,     forKey: .scanVizMode) ?? .dots
        // OccupancyGrid
        freeR          = try c.decodeIfPresent(Double.self, forKey: .freeR)          ?? 0.94
        freeG          = try c.decodeIfPresent(Double.self, forKey: .freeG)          ?? 0.94
        freeB          = try c.decodeIfPresent(Double.self, forKey: .freeB)          ?? 0.94
        unknownR       = try c.decodeIfPresent(Double.self, forKey: .unknownR)       ?? 0.55
        unknownG       = try c.decodeIfPresent(Double.self, forKey: .unknownG)       ?? 0.65
        unknownB       = try c.decodeIfPresent(Double.self, forKey: .unknownB)       ?? 0.75
        showGridLines  = try c.decodeIfPresent(Bool.self,   forKey: .showGridLines)  ?? false
        showUnknownCells = try c.decodeIfPresent(Bool.self, forKey: .showUnknownCells) ?? true
        // PointCloud2
        pc2ColorMode      = try c.decodeIfPresent(PC2ColorMode.self, forKey: .pc2ColorMode)      ?? .flat
        pc2ColorFieldName = try c.decodeIfPresent(String.self,       forKey: .pc2ColorFieldName) ?? "z"
        pc2HeightMin      = try c.decodeIfPresent(Double.self,        forKey: .pc2HeightMin)      ?? -0.5
        pc2HeightMax      = try c.decodeIfPresent(Double.self,        forKey: .pc2HeightMax)      ?? 2.0
        pc2StrideN        = try c.decodeIfPresent(Int.self,           forKey: .pc2StrideN)        ?? 1
        // Odometry
        showOdomTrail    = try c.decodeIfPresent(Bool.self,   forKey: .showOdomTrail)    ?? true
        odomTrailLength  = try c.decodeIfPresent(Int.self,    forKey: .odomTrailLength)  ?? 100
        odomTrailR       = try c.decodeIfPresent(Double.self, forKey: .odomTrailR)       ?? 0.18
        odomTrailG       = try c.decodeIfPresent(Double.self, forKey: .odomTrailG)       ?? 0.73
        odomTrailB       = try c.decodeIfPresent(Double.self, forKey: .odomTrailB)       ?? 0.69
        showVelocityArrow = try c.decodeIfPresent(Bool.self,  forKey: .showVelocityArrow) ?? false
        // Path
        showPathWaypoints  = try c.decodeIfPresent(Bool.self,   forKey: .showPathWaypoints)  ?? true
        pathWaypointEveryN = try c.decodeIfPresent(Int.self,    forKey: .pathWaypointEveryN) ?? 5
        pathWaypointSize   = try c.decodeIfPresent(Double.self, forKey: .pathWaypointSize)   ?? 4.0
        // MarkerArray
        markerNamespaceFilter = try c.decodeIfPresent(String.self, forKey: .markerNamespaceFilter) ?? ""
        // Octomap
        octomapVoxelScale   = try c.decodeIfPresent(Double.self, forKey: .octomapVoxelScale)   ?? 1.0
        octomapMaxDepth     = try c.decodeIfPresent(Int.self,    forKey: .octomapMaxDepth)     ?? -1
        octomapShowOccupied = try c.decodeIfPresent(Bool.self,   forKey: .octomapShowOccupied) ?? true
        octomapShowFree     = try c.decodeIfPresent(Bool.self,   forKey: .octomapShowFree)     ?? false
        octomapShowUnknown  = try c.decodeIfPresent(Bool.self,   forKey: .octomapShowUnknown)  ?? false
        octomapOccupiedR    = try c.decodeIfPresent(Double.self, forKey: .octomapOccupiedR)    ?? 0.2
        octomapOccupiedG    = try c.decodeIfPresent(Double.self, forKey: .octomapOccupiedG)    ?? 0.6
        octomapOccupiedB    = try c.decodeIfPresent(Double.self, forKey: .octomapOccupiedB)    ?? 0.8
        octomapFreeR        = try c.decodeIfPresent(Double.self, forKey: .octomapFreeR)        ?? 0.8
        octomapFreeG        = try c.decodeIfPresent(Double.self, forKey: .octomapFreeG)        ?? 0.9
        octomapFreeB        = try c.decodeIfPresent(Double.self, forKey: .octomapFreeB)        ?? 1.0
        octomapAlpha        = try c.decodeIfPresent(Double.self, forKey: .octomapAlpha)        ?? 0.7
        octomapStrideN      = try c.decodeIfPresent(Int.self,    forKey: .octomapStrideN)      ?? 1
        // Robot Model
        robotModelTintR         = try c.decodeIfPresent(Double.self,         forKey: .robotModelTintR)         ?? 1.0
        robotModelTintG         = try c.decodeIfPresent(Double.self,         forKey: .robotModelTintG)         ?? 1.0
        robotModelTintB         = try c.decodeIfPresent(Double.self,         forKey: .robotModelTintB)         ?? 1.0
        robotModelHiddenLinks   = try c.decodeIfPresent(Set<String>.self,    forKey: .robotModelHiddenLinks)   ?? []
        robotModelMeshOverrides = try c.decodeIfPresent([String: String].self, forKey: .robotModelMeshOverrides) ?? [:]
        // Mesh Map
        meshMapR              = try c.decodeIfPresent(Double.self, forKey: .meshMapR)              ?? 0.9
        meshMapG              = try c.decodeIfPresent(Double.self, forKey: .meshMapG)              ?? 0.9
        meshMapB              = try c.decodeIfPresent(Double.self, forKey: .meshMapB)              ?? 0.9
        meshMapShowWireframe  = try c.decodeIfPresent(Bool.self,   forKey: .meshMapShowWireframe)  ?? false
        meshMapDoubleSided    = try c.decodeIfPresent(Bool.self,   forKey: .meshMapDoubleSided)    ?? true
        meshMapStrideN        = try c.decodeIfPresent(Int.self,    forKey: .meshMapStrideN)        ?? 1
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(r,            forKey: .r)
        try c.encode(g,            forKey: .g)
        try c.encode(b,            forKey: .b)
        try c.encode(opacity,      forKey: .opacity)
        try c.encode(pointSize,    forKey: .pointSize)
        try c.encode(decaySeconds, forKey: .decaySeconds)
        try c.encode(axisLength,      forKey: .axisLength)
        try c.encode(showFrameNames,  forKey: .showFrameNames)
        try c.encode(showFrameLinks,  forKey: .showFrameLinks)
        try c.encode(hiddenFrames,    forKey: .hiddenFrames)
        try c.encode(tfFreshThresholdSec, forKey: .tfFreshThresholdSec)
        try c.encode(tfStaleThresholdSec, forKey: .tfStaleThresholdSec)
        try c.encode(linkLineWidth,  forKey: .linkLineWidth)
        try c.encode(linkLineStyle,  forKey: .linkLineStyle)
        try c.encode(linkLineR,      forKey: .linkLineR)
        try c.encode(linkLineG,      forKey: .linkLineG)
        try c.encode(linkLineB,      forKey: .linkLineB)
        try c.encode(axisLineWidth,  forKey: .axisLineWidth)
        try c.encode(axisShowX,      forKey: .axisShowX)
        try c.encode(axisShowY,      forKey: .axisShowY)
        try c.encode(axisShowZ,      forKey: .axisShowZ)
        try c.encode(axisShowLabels, forKey: .axisShowLabels)
        try c.encode(axisLabelSize,  forKey: .axisLabelSize)
        try c.encode(frameNodeSize,  forKey: .frameNodeSize)
        try c.encode(frameNodeShape, forKey: .frameNodeShape)
        try c.encode(frameColorMode, forKey: .frameColorMode)
        try c.encode(colorMode,   forKey: .colorMode)
        try c.encode(rangeMin,    forKey: .rangeMin)
        try c.encode(rangeMax,    forKey: .rangeMax)
        try c.encode(scanVizMode, forKey: .scanVizMode)
        try c.encode(freeR,          forKey: .freeR)
        try c.encode(freeG,          forKey: .freeG)
        try c.encode(freeB,          forKey: .freeB)
        try c.encode(unknownR,       forKey: .unknownR)
        try c.encode(unknownG,       forKey: .unknownG)
        try c.encode(unknownB,       forKey: .unknownB)
        try c.encode(showGridLines,  forKey: .showGridLines)
        try c.encode(showUnknownCells, forKey: .showUnknownCells)
        try c.encode(pc2ColorMode,      forKey: .pc2ColorMode)
        try c.encode(pc2ColorFieldName, forKey: .pc2ColorFieldName)
        try c.encode(pc2HeightMin,      forKey: .pc2HeightMin)
        try c.encode(pc2HeightMax,      forKey: .pc2HeightMax)
        try c.encode(pc2StrideN,        forKey: .pc2StrideN)
        try c.encode(showOdomTrail,    forKey: .showOdomTrail)
        try c.encode(odomTrailLength,  forKey: .odomTrailLength)
        try c.encode(odomTrailR,       forKey: .odomTrailR)
        try c.encode(odomTrailG,       forKey: .odomTrailG)
        try c.encode(odomTrailB,       forKey: .odomTrailB)
        try c.encode(showVelocityArrow, forKey: .showVelocityArrow)
        try c.encode(showPathWaypoints,  forKey: .showPathWaypoints)
        try c.encode(pathWaypointEveryN, forKey: .pathWaypointEveryN)
        try c.encode(pathWaypointSize,   forKey: .pathWaypointSize)
        try c.encode(markerNamespaceFilter, forKey: .markerNamespaceFilter)
        // Octomap
        try c.encode(octomapVoxelScale,   forKey: .octomapVoxelScale)
        try c.encode(octomapMaxDepth,     forKey: .octomapMaxDepth)
        try c.encode(octomapShowOccupied, forKey: .octomapShowOccupied)
        try c.encode(octomapShowFree,     forKey: .octomapShowFree)
        try c.encode(octomapShowUnknown,  forKey: .octomapShowUnknown)
        try c.encode(octomapOccupiedR,    forKey: .octomapOccupiedR)
        try c.encode(octomapOccupiedG,    forKey: .octomapOccupiedG)
        try c.encode(octomapOccupiedB,    forKey: .octomapOccupiedB)
        try c.encode(octomapFreeR,        forKey: .octomapFreeR)
        try c.encode(octomapFreeG,        forKey: .octomapFreeG)
        try c.encode(octomapFreeB,        forKey: .octomapFreeB)
        try c.encode(octomapAlpha,        forKey: .octomapAlpha)
        try c.encode(octomapStrideN,      forKey: .octomapStrideN)
        // Robot Model
        try c.encode(robotModelTintR,         forKey: .robotModelTintR)
        try c.encode(robotModelTintG,         forKey: .robotModelTintG)
        try c.encode(robotModelTintB,         forKey: .robotModelTintB)
        try c.encode(robotModelHiddenLinks,   forKey: .robotModelHiddenLinks)
        try c.encode(robotModelMeshOverrides, forKey: .robotModelMeshOverrides)
        // Mesh Map
        try c.encode(meshMapR,              forKey: .meshMapR)
        try c.encode(meshMapG,              forKey: .meshMapG)
        try c.encode(meshMapB,              forKey: .meshMapB)
        try c.encode(meshMapShowWireframe,  forKey: .meshMapShowWireframe)
        try c.encode(meshMapDoubleSided,    forKey: .meshMapDoubleSided)
        try c.encode(meshMapStrideN,        forKey: .meshMapStrideN)
    }
}

// MARK: - Display Layer

/// One renderable layer in the 3D scene — a topic subscription + settings.
public struct DisplayLayer: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    /// ROS topic name. Empty string for built-in layers (e.g. TF Frames).
    public var topic: String
    public var type: LayerType
    public var settings: LayerSettings
    public var isVisible: Bool

    public init(topic: String = "", type: LayerType, isVisible: Bool = true, layerID: UUID? = nil) {
        self.id = layerID ?? UUID()
        self.topic = topic
        self.type = type
        self.settings = LayerSettings()
        self.isVisible = isVisible
    }

    /// Human-readable label shown in the panel.
    public var displayLabel: String {
        switch type {
        case .tfFrames:  return "TF Frames"
        case .robotModel: return "Robot Model"
        default:         return topic
        }
    }
}

// MARK: - Viewer3DConfig

/// Configuration for a ``Viewer3DView``.
public struct Viewer3DConfig: Sendable, Equatable {
    /// TF frame all geometry is expressed relative to.
    public var fixedFrame: String

    public init(fixedFrame: String = "world") {
        self.fixedFrame = fixedFrame
    }

    // MARK: - Helpers

    /// Builds the default seed layer list from a live topic list.
    /// Called once when a connection first reports available topics.
    public static func seedLayers(from topics: [TopicDescriptor]) -> [DisplayLayer] {
        let detected = topics.compactMap { td -> DisplayLayer? in
            guard let type = LayerType.detect(from: td.schemaName) else { return nil }
            return DisplayLayer(topic: td.name, type: type)
        }
        .sorted { $0.topic < $1.topic }
        return detected
    }

    // MARK: - Backward-compat accessors

    public func pointCloudTopics(from layers: [DisplayLayer]) -> [String] {
        layers.filter { $0.type == .pointCloud2 && $0.isVisible }.map { $0.topic }
    }

    public func laserScanTopics(from layers: [DisplayLayer]) -> [String] {
        layers.filter { $0.type == .laserScan && $0.isVisible }.map { $0.topic }
    }
}

// MARK: - Viewer3DProfileConfig

/// Persisted 3D viewer configuration for a single connection profile.
/// Stored per-profile in UserDefaults, keyed by profile UUID.
public struct Viewer3DProfileConfig: Codable, Sendable, Equatable {
    /// Ordered list of layers the user has configured.
    public var layers: [DisplayLayer]
    /// Opaque JSON blob encoding the internal `Camera` struct.
    /// Stored as raw bytes so PointCloudRenderer owns the type.
    public var cameraData: Data?
    /// The TF fixed frame selected for this profile.
    public var fixedFrame: String
    /// Path to a manually loaded URDF file, restored on reconnect.
    public var urdfFileURL: URL?

    public init(layers: [DisplayLayer] = [], cameraData: Data? = nil, fixedFrame: String = "world", urdfFileURL: URL? = nil) {
        self.layers = layers
        self.cameraData = cameraData
        self.fixedFrame = fixedFrame
        self.urdfFileURL = urdfFileURL
    }

    // MARK: - UserDefaults helpers

    /// UserDefaults key for a given profile ID.
    public static func defaultsKey(for profileID: String) -> String {
        "viewer3d.config.\(profileID)"
    }

    /// Loads a saved config for the given profile ID, or nil if none exists.
    public static func load(for profileID: String) -> Viewer3DProfileConfig? {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey(for: profileID)),
              let config = try? JSONDecoder().decode(Viewer3DProfileConfig.self, from: data)
        else { return nil }
        return config
    }

    /// Saves this config for the given profile ID.
    public func save(for profileID: String) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey(for: profileID))
    }
}
