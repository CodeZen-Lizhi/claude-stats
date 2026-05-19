import CoreGraphics
import Observation

@MainActor
@Observable
final class FloatingStatsPanelState {
    var edge: FloatingPanelEdge = .right
    var isExpanded = false
    var expandedContentPhase: FloatingStatsExpandedContentPhase = .hidden
    var showsCollapsedContent = true
    var isDocked = true
    var edgeReleaseProgress: CGFloat = FloatingPanelDragMotion.dockedEdgeReleaseProgress
}
