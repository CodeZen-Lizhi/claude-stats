import CoreGraphics
import Foundation
import Testing
@testable import ClaudeStats

@Suite("NotchIslandHoverCoordinator")
@MainActor
struct NotchIslandHoverCoordinatorTests {
    @Test("Transient hover exit inside the island does not collapse")
    func transientExitInsideIslandDoesNotCollapse() async throws {
        let probe = HoverCoordinatorProbe(
            mouseLocation: CGPoint(x: 120, y: 80),
            panelFrames: [CGRect(x: 0, y: 0, width: 240, height: 160)]
        )
        let coordinator = makeCoordinator(probe: probe)

        coordinator.handleHoverChanged(true)
        coordinator.handleHoverChanged(false)
        try await Task.sleep(for: .milliseconds(40))

        #expect(probe.expanded == true)
    }

    @Test("Hover exit outside every island panel collapses after delay")
    func exitOutsideIslandCollapsesAfterDelay() async throws {
        let probe = HoverCoordinatorProbe(
            mouseLocation: CGPoint(x: 400, y: 240),
            panelFrames: [CGRect(x: 0, y: 0, width: 240, height: 160)]
        )
        let coordinator = makeCoordinator(probe: probe)

        coordinator.handleHoverChanged(true)
        coordinator.handleHoverChanged(false)
        try await Task.sleep(for: .milliseconds(40))

        #expect(probe.expanded == false)
    }

    @Test("Hover re-entry cancels a pending collapse")
    func reentryCancelsPendingCollapse() async throws {
        let probe = HoverCoordinatorProbe(
            mouseLocation: CGPoint(x: 400, y: 240),
            panelFrames: [CGRect(x: 0, y: 0, width: 240, height: 160)]
        )
        let coordinator = makeCoordinator(probe: probe)

        coordinator.handleHoverChanged(true)
        coordinator.handleHoverChanged(false)
        coordinator.handleHoverChanged(true)
        try await Task.sleep(for: .milliseconds(40))

        #expect(probe.expanded == true)
    }

    private func makeCoordinator(probe: HoverCoordinatorProbe) -> NotchIslandHoverCoordinator {
        NotchIslandHoverCoordinator(
            collapseDelay: .milliseconds(20),
            mouseLocationProvider: { probe.mouseLocation },
            panelFramesProvider: { probe.panelFrames },
            setExpanded: { probe.expanded = $0 }
        )
    }
}

@MainActor
private final class HoverCoordinatorProbe {
    var expanded = false
    var mouseLocation: CGPoint
    var panelFrames: [CGRect]

    init(mouseLocation: CGPoint, panelFrames: [CGRect]) {
        self.mouseLocation = mouseLocation
        self.panelFrames = panelFrames
    }
}
