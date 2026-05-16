import CoreGraphics
import Observation

@MainActor
@Observable
final class FloatingStatsPanelState {
    var edge: FloatingPanelEdge = .right
    var isExpanded = false
    var isDocked = true
    var edgeReleaseProgress: CGFloat = FloatingPanelDragMotion.dockedEdgeReleaseProgress
}
