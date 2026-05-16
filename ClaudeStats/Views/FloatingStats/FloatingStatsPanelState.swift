import Observation

@MainActor
@Observable
final class FloatingStatsPanelState {
    var edge: FloatingPanelEdge = .right
    var isExpanded = false
}
