import Foundation
import simd
import RobotModelCore

// MARK: - URDF XML delegate

/// Foundation `XMLParser` delegate that builds a ``RobotModel`` from a URDF document.
///
/// The delegate processes these elements:
/// - `<robot>` — root; `name` attribute is recorded but not exposed in 0.1.0
/// - `<link>` — name + optional `<visual>/<geometry>/<mesh filename>`
/// - `<joint>` — name, type, parent, child, `<origin>`, `<axis>`
/// - `<material>` — parsed but not surfaced in RobotModel 0.1.0
///
/// Xacro directives must be stripped by ``XacroPreprocessor`` before parsing.
final class URDFXMLDelegate: NSObject, XMLParserDelegate, @unchecked Sendable {

    // MARK: - State

    private enum Context {
        case none
        case link
        case joint
        case visual          // inside <link>/<visual>
        case geometry        // inside <visual>/<geometry>
        case jointOrigin
        case jointAxis
        case parentChild
    }

    private var context: Context = .none
    private var elementStack: [String] = []

    // Accumulated data
    private var links: [Link] = []
    private var joints: [Joint] = []
    private var rootCandidates: Set<String> = []
    private var childSet: Set<String> = []

    // Current link being assembled
    private var currentLinkName: String = ""
    private var currentMeshFilename: String? = nil
    private var currentMeshScale: SIMD3<Float> = SIMD3(1, 1, 1)
    private var currentVisualOrigin: Transform = .identity

    // Current joint being assembled
    private var currentJointName: String = ""
    private var currentJointType: JointType = .fixed
    private var currentParent: String = ""
    private var currentChild: String = ""
    private var currentAxis: SIMD3<Float> = SIMD3(1, 0, 0)
    private var currentOrigin: Transform = .identity

    // Error accumulation
    private(set) var parseError: URDFParserError? = nil
    private var foundRoot = false

    // MARK: - Result

    /// Returns the completed `RobotModel`. Call after parsing succeeds.
    func buildModel() throws -> RobotModel {
        if let err = parseError { throw err }
        guard foundRoot else { throw URDFParserError.missingRootElement }

        // Determine root link: link that is never a child
        let allLinkNames = Set(links.map { $0.name })
        let nonChildLinks = allLinkNames.subtracting(childSet)
        let rootLink = nonChildLinks.first ?? links.first?.name ?? ""

        return RobotModel(links: links, joints: joints, rootLink: rootLink)
    }

    // MARK: - XMLParserDelegate

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes: [String: String] = [:])
    {
        elementStack.append(elementName)

        switch elementName {
        case "robot":
            foundRoot = true

        case "link":
            guard let name = attributes["name"] else {
                parseError = .missingAttribute(element: "link", attribute: "name")
                parser.abortParsing()
                return
            }
            currentLinkName = name
            currentMeshFilename = nil
            currentMeshScale = SIMD3(1, 1, 1)
            currentVisualOrigin = .identity
            context = .link

        case "joint":
            guard let name = attributes["name"] else {
                parseError = .missingAttribute(element: "joint", attribute: "name")
                parser.abortParsing()
                return
            }
            guard let typeStr = attributes["type"] else {
                parseError = .missingAttribute(element: "joint", attribute: "type")
                parser.abortParsing()
                return
            }
            currentJointName = name
            currentJointType = JointType(urdfString: typeStr)
            currentParent = ""
            currentChild = ""
            currentAxis = SIMD3(1, 0, 0)
            currentOrigin = .identity
            context = .joint

        case "visual":
            if context == .link { context = .visual }

        case "geometry":
            if context == .visual { context = .geometry }

        case "mesh":
            if context == .geometry {
                currentMeshFilename = attributes["filename"]
                if let scaleStr = attributes["scale"] {
                    let parts = scaleStr.split(separator: " ").compactMap { Float($0) }
                    if parts.count == 3 { currentMeshScale = SIMD3(parts[0], parts[1], parts[2]) }
                }
            }

        case "origin":
            if context == .joint {
                currentOrigin = parseOrigin(attributes)
            } else if context == .visual {
                currentVisualOrigin = parseOrigin(attributes)
            }

        case "axis":
            if context == .joint {
                currentAxis = parseAxis(attributes)
            }

        case "parent":
            if context == .joint {
                currentParent = attributes["link"] ?? ""
            }

        case "child":
            if context == .joint {
                currentChild = attributes["link"] ?? ""
            }

        default:
            break
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?)
    {
        elementStack.removeLast()

        switch elementName {
        case "link":
            links.append(Link(name: currentLinkName, meshKey: currentMeshFilename, meshScale: currentMeshScale, visualOrigin: currentVisualOrigin))
            context = .none

        case "joint":
            let joint = Joint(
                name: currentJointName,
                parent: currentParent,
                child: currentChild,
                type: currentJointType,
                axis: currentAxis,
                origin: currentOrigin)
            joints.append(joint)
            childSet.insert(currentChild)
            context = .none

        case "visual":
            if context == .visual { context = .link }

        case "geometry":
            if context == .geometry { context = .visual }

        default:
            break
        }
    }

    func parser(_ parser: XMLParser, parseErrorOccurred error: Error) {
        parseError = .xmlParseError(error.localizedDescription)
    }

    // MARK: - Attribute parsing helpers

    private func parseOrigin(_ attrs: [String: String]) -> Transform {
        var translation = SIMD3<Float>(0, 0, 0)
        var rpy = SIMD3<Float>(0, 0, 0)

        if let xyz = attrs["xyz"] {
            let parts = xyz.split(separator: " ").compactMap { Float($0) }
            if parts.count == 3 { translation = SIMD3(parts[0], parts[1], parts[2]) }
        }
        if let rpyStr = attrs["rpy"] {
            let parts = rpyStr.split(separator: " ").compactMap { Float($0) }
            if parts.count == 3 { rpy = SIMD3(parts[0], parts[1], parts[2]) }
        }

        let rotation = simd_quatf(roll: rpy.x, pitch: rpy.y, yaw: rpy.z)
        var t = Transform()
        t.translation = translation
        t.rotation = rotation
        return t
    }

    private func parseAxis(_ attrs: [String: String]) -> SIMD3<Float> {
        guard let xyz = attrs["xyz"] else { return SIMD3(1, 0, 0) }
        let parts = xyz.split(separator: " ").compactMap { Float($0) }
        guard parts.count == 3 else { return SIMD3(1, 0, 0) }
        return SIMD3(parts[0], parts[1], parts[2])
    }
}

// MARK: - JointType from URDF string

extension JointType {
    init(urdfString: String) {
        switch urdfString {
        case "revolute":   self = .revolute
        case "continuous": self = .continuous
        case "prismatic":  self = .prismatic
        case "fixed":      self = .fixed
        case "floating":   self = .floating
        case "planar":     self = .planar
        default:           self = .fixed
        }
    }
}

// MARK: - RPY → quaternion

private extension simd_quatf {
    /// Constructs a quaternion from ROS-convention roll-pitch-yaw (intrinsic XYZ rotations).
    init(roll: Float, pitch: Float, yaw: Float) {
        let cr = cos(roll / 2), sr = sin(roll / 2)
        let cp = cos(pitch / 2), sp = sin(pitch / 2)
        let cy = cos(yaw / 2), sy = sin(yaw / 2)
        let w = cr * cp * cy + sr * sp * sy
        let x = sr * cp * cy - cr * sp * sy
        let y = cr * sp * cy + sr * cp * sy
        let z = cr * cp * sy - sr * sp * cy
        self.init(ix: x, iy: y, iz: z, r: w)
    }
}
