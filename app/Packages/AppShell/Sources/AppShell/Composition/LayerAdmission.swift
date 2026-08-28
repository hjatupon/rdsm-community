import Foundation
import Viewer3DUI

/// What caused a write to the viewer's layer list.
public enum LayerChangeSource: Sendable {
    /// A direct user gesture — adding, duplicating or revealing a layer.
    case user
    /// Rehydrating a saved per-profile layout on connect. Never a purchase moment, so a
    /// policy that refuses layers here must do it silently.
    case restore
}

/// Open-core seam: lets an edition cap the 3D viewer's layer list.
///
/// `nil` by default, which is what this build leaves it as — every write is admitted
/// unchanged and there is no behavioural difference of any kind. An edition that wants a
/// limit installs a closure from its own composition root; `AppShell` never imports it,
/// exactly like `ProUIRegistry`.
///
/// The hook sits on the single commit path (`AppServices.viewer3DLayers`) rather than on
/// the individual call sites deliberately: layers are written from six places across three
/// packages — the layer picker, the duplicate action, the visibility toggle, the URDF load,
/// the static-map load and the mesh-map load — and a policy spread across six checks only
/// stays closed for as long as all six agree. A seventh call site added later would not
/// have to remember anything.
@MainActor
public enum LayerAdmission {
    /// Given the proposed list, the previous list and what caused the change, returns the
    /// list that may actually be committed. Return `proposed` to admit it unchanged.
    public static var clamp: (@MainActor (_ proposed: [DisplayLayer],
                                          _ previous: [DisplayLayer],
                                          _ source: LayerChangeSource) -> [DisplayLayer])?
}
