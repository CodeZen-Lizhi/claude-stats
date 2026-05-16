import AppKit
import Observation
import SwiftUI

@MainActor
final class FloatingStatsPanelController {
    private static let dragActivationDistance: CGFloat = 22

    private weak var environment: AppEnvironment?
    private weak var preferences: Preferences?
    private let state = FloatingStatsPanelState()

    private var panel: NSPanel?
    private var dragStartFrame: CGRect?
    private var dragHasActivated = false
    private var collapseTask: Task<Void, Never>?
    private var screenObserver: NSObjectProtocol?
    private var isStarted = false
    private var isDragging = false
    private var isHovering = false

    func start(environment: AppEnvironment) {
        guard !isStarted else { return }
        isStarted = true
        self.environment = environment
        self.preferences = environment.preferences
        state.edge = environment.preferences.floatingTabEdge
        observePreferences()
        syncWithPreferences()
        observeScreenChanges()
    }

    private func observePreferences() {
        guard let preferences else { return }
        withObservationTracking {
            _ = preferences.floatingTabEnabled
            _ = preferences.floatingTabEdge
            _ = preferences.floatingTabAnchor
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.syncWithPreferences()
                self?.observePreferences()
            }
        }
    }

    private func syncWithPreferences() {
        guard let preferences else { return }
        if preferences.floatingTabEnabled {
            state.edge = preferences.floatingTabEdge
            ensurePanel()
            guard !isDragging else { return }
            applyStoredFrame(animated: false)
        } else {
            closePanel()
        }
    }

    private func ensurePanel() {
        guard panel == nil, let environment, let preferences else { return }
        let screen = bestScreen(for: nil)
        let frame = FloatingPanelGeometry.frame(
            edge: preferences.floatingTabEdge,
            anchor: preferences.floatingTabAnchor,
            in: screen.visibleFrame,
            expanded: false
        )

        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.title = "Claude Stats Floating Tab"

        let rootView = FloatingStatsPanelView(
            state: state,
            onHoverChanged: { [weak self] hovering in
                self?.setHovering(hovering)
            },
            onDragChanged: { [weak self] translation in
                self?.dragChanged(translation: translation)
            },
            onDragEnded: { [weak self] translation in
                self?.dragEnded(translation: translation)
            }
        )
        .environment(environment)

        panel.contentView = NSHostingView(rootView: rootView)
        self.panel = panel
        panel.orderFrontRegardless()
    }

    private func closePanel() {
        collapseTask?.cancel()
        collapseTask = nil
        panel?.orderOut(nil)
        panel = nil
        dragStartFrame = nil
        dragHasActivated = false
        isDragging = false
        isHovering = false
        state.isExpanded = false
    }

    private func setHovering(_ hovering: Bool) {
        isHovering = hovering
        if hovering {
            collapseTask?.cancel()
            collapseTask = nil
            setExpanded(true, animated: true)
        } else {
            scheduleCollapse()
        }
    }

    private func scheduleCollapse() {
        collapseTask?.cancel()
        collapseTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            await MainActor.run {
                guard let self, !self.isHovering, !self.isDragging else { return }
                self.setExpanded(false, animated: true)
            }
        }
    }

    private func setExpanded(_ expanded: Bool, animated: Bool) {
        guard state.isExpanded != expanded else { return }
        state.isExpanded = expanded
        applyStoredFrame(animated: animated)
    }

    private func dragChanged(translation: CGSize) {
        guard let panel else { return }
        collapseTask?.cancel()
        collapseTask = nil
        if dragStartFrame == nil {
            dragStartFrame = panel.frame
            isDragging = true
            dragHasActivated = false
        }
        guard let dragStartFrame else { return }
        if !dragHasActivated {
            guard translation.distance >= Self.dragActivationDistance else { return }
            dragHasActivated = true
        }
        let nextFrame = dragStartFrame.offsetBy(dx: translation.width, dy: -translation.height)
        panel.setFrame(nextFrame, display: true)
    }

    private func dragEnded(translation: CGSize) {
        guard let panel, let preferences else { return }
        let didActivate = dragHasActivated
        if didActivate, let dragStartFrame {
            let nextFrame = dragStartFrame.offsetBy(dx: translation.width, dy: -translation.height)
            panel.setFrame(nextFrame, display: true)
        }
        dragStartFrame = nil
        dragHasActivated = false
        isDragging = false

        guard didActivate else {
            if !isHovering {
                scheduleCollapse()
            }
            return
        }

        let center = panel.frame.center
        let screen = bestScreen(for: center)
        let edge = FloatingPanelGeometry.nearestEdge(to: center, in: screen.visibleFrame)
        let size = FloatingPanelGeometry.size(edge: edge, expanded: state.isExpanded)
        let anchor = FloatingPanelGeometry.anchor(for: center, edge: edge, in: screen.visibleFrame, size: size)

        state.edge = edge
        preferences.floatingTabEdge = edge
        preferences.floatingTabAnchor = anchor
        applyStoredFrame(animated: true)

        if !isHovering {
            scheduleCollapse()
        }
    }

    private func applyStoredFrame(animated: Bool) {
        guard let panel, let preferences else { return }
        guard !isDragging else { return }
        let screen = bestScreen(for: panel.frame.center)
        let anchor = FloatingPanelGeometry.clampedAnchor(
            preferences.floatingTabAnchor,
            edge: preferences.floatingTabEdge,
            size: FloatingPanelGeometry.size(edge: preferences.floatingTabEdge, expanded: state.isExpanded),
            in: screen.visibleFrame
        )
        if anchor != preferences.floatingTabAnchor {
            preferences.floatingTabAnchor = anchor
        }
        let frame = FloatingPanelGeometry.frame(
            edge: preferences.floatingTabEdge,
            anchor: anchor,
            in: screen.visibleFrame,
            expanded: state.isExpanded
        )

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.allowsImplicitAnimation = true
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
    }

    private func observeScreenChanges() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.applyStoredFrame(animated: true)
            }
        }
    }

    private func bestScreen(for point: CGPoint?) -> NSScreen {
        let screens = NSScreen.screens
        if let point {
            if let containing = screens.first(where: { $0.visibleFrame.contains(point) || $0.frame.contains(point) }) {
                return containing
            }
            if let nearest = screens.min(by: { distance(from: point, to: $0.frame) < distance(from: point, to: $1.frame) }) {
                return nearest
            }
        }
        guard let fallback = NSScreen.main ?? screens.first else {
            preconditionFailure("Floating stats panel requires at least one screen")
        }
        return fallback
    }

    private func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return hypot(dx, dy)
    }
}

private extension CGRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }
}

private extension CGSize {
    var distance: CGFloat {
        hypot(width, height)
    }
}
