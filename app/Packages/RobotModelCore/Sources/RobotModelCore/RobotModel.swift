/// A robot's kinematic tree: `links` (bodies), `joints` (edges), and the `rootLink`
/// the tree is anchored to.
///
/// The renderer consumes this structure — it never parses URDF/XML (Contract C7).
/// Building a `RobotModel` from URDF is M9's job; the renderer's demo constructs one
/// directly so the rendering library stays parser-free.
public struct RobotModel: Sendable, Equatable {
    public let links: [Link]
    public let joints: [Joint]
    public let rootLink: String

    public init(links: [Link], joints: [Joint], rootLink: String) {
        self.links = links
        self.joints = joints
        self.rootLink = rootLink
    }
}
