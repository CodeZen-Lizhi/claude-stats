import CoreGraphics
import Foundation

@MainActor
final class NotchIslandHoverCoordinator {
    static let defaultCollapseDelay: Duration = .milliseconds(220)

    private let collapseDelay: Duration
    private let mouseLocationProvider: @MainActor () -> CGPoint
    private let panelFramesProvider: @MainActor () -> [CGRect]
    private let setExpanded: @MainActor (Bool) -> Void
    private var pendingCollapseTask: Task<Void, Never>?

    init(
        collapseDelay: Duration = NotchIslandHoverCoordinator.defaultCollapseDelay,
        mouseLocationProvider: @escaping @MainActor () -> CGPoint,
        panelFramesProvider: @escaping @MainActor () -> [CGRect],
        setExpanded: @escaping @MainActor (Bool) -> Void
    ) {
        self.collapseDelay = collapseDelay
        self.mouseLocationProvider = mouseLocationProvider
        self.panelFramesProvider = panelFramesProvider
        self.setExpanded = setExpanded
    }

    deinit {
        pendingCollapseTask?.cancel()
    }

    func handleHoverChanged(_ hovering: Bool) {
        if hovering {
            cancelPendingCollapse()
            setExpanded(true)
        } else {
            scheduleCollapseIfMouseLeaves()
        }
    }

    func collapseImmediately() {
        cancelPendingCollapse()
        setExpanded(false)
    }

    func cancelPendingCollapse() {
        pendingCollapseTask?.cancel()
        pendingCollapseTask = nil
    }

    private func scheduleCollapseIfMouseLeaves() {
        cancelPendingCollapse()
        let delay = collapseDelay
        pendingCollapseTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }

            guard let self, !self.isMouseInsideIslandPanel() else { return }
            self.setExpanded(false)
            self.pendingCollapseTask = nil
        }
    }

    private func isMouseInsideIslandPanel() -> Bool {
        let mouseLocation = mouseLocationProvider()
        return panelFramesProvider().contains { frame in
            frame.insetBy(dx: -4, dy: -4).contains(mouseLocation)
        }
    }
}
