import CoreGraphics
import Observation

@MainActor
@Observable
final class FloatingStatsPanelState {
    var edge: FloatingPanelEdge = .right
    var isExpanded = false
    var showsExpandedContent = false
    var isDocked = true
    var edgeReleaseProgress: CGFloat = FloatingPanelDragMotion.dockedEdgeReleaseProgress
}
