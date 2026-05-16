import AppKit
import Observation
import SwiftUI

@MainActor
final class FloatingStatsPanelController {
    private enum DragState {
        case idle
        case pending(startMouse: CGPoint, startFrame: CGRect)
        case active(startMouse: CGPoint, startFrame: CGRect)

        var isDragging: Bool {
            switch self {
            case .idle: false
            case .pending, .active: true
            }
        }
    }

    private enum Placement {
        case docked
        case detached(frame: CGRect)

        var isDocked: Bool {
            switch self {
            case .docked: true
            case .detached: false
            }
        }
    }

    private weak var environment: AppEnvironment?
    private weak var preferences: Preferences?
    private let state = FloatingStatsPanelState()

    private var panel: NSPanel?
    private var placement: Placement = .docked
    private var dragState: DragState = .idle
    private var collapseTask: Task<Void, Never>?
    private var screenObserver: NSObjectProtocol?
    private var suppressPreferenceSync = false
    private var frameTransitionID = 0
    private var isApplyingFrame = false
    private var isStarted = false
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
                if self?.suppressPreferenceSync == true {
                    self?.observePreferences()
                    return
                }
                self?.syncWithPreferences()
                self?.observePreferences()
            }
        }
    }

    private func syncWithPreferences() {
        guard let preferences else { return }
        if preferences.floatingTabEnabled {
            placement = .docked
            state.isDocked = true
            setEdgeReleaseProgress(FloatingPanelDragMotion.dockedEdgeReleaseProgress, animated: false)
            state.edge = preferences.floatingTabEdge
            ensurePanel()
            guard !dragState.isDragging else { return }
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
            onDragBegan: { [weak self] mouseLocation in
                self?.dragBegan(at: mouseLocation)
            },
            onDragMoved: { [weak self] mouseLocation in
                self?.dragMoved(to: mouseLocation)
            },
            onDragEnded: { [weak self] mouseLocation in
                self?.dragEnded(at: mouseLocation)
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
        placement = .docked
        dragState = .idle
        frameTransitionID += 1
        isApplyingFrame = false
        isHovering = false
        state.isExpanded = false
        state.isDocked = true
        setEdgeReleaseProgress(FloatingPanelDragMotion.dockedEdgeReleaseProgress, animated: false)
    }

    private func setHovering(_ hovering: Bool) {
        guard !dragState.isDragging else { return }
        guard !isApplyingFrame else { return }
        if !hovering, isMouseInsidePanel() {
            isHovering = true
            return
        }
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
                guard let self, !self.isHovering, !self.dragState.isDragging else { return }
                guard !self.isMouseInsidePanel() else {
                    self.isHovering = true
                    return
                }
                self.collapseCurrentPlacement(animated: true)
            }
        }
    }

    private func setExpanded(_ expanded: Bool, animated: Bool) {
        guard state.isExpanded != expanded else { return }
        if !expanded, !placement.isDocked {
            dockDetachedPanel(animated: animated)
            return
        }
        state.isExpanded = expanded
        applyStoredFrame(animated: animated)
    }

    private func dragBegan(at mouseLocation: CGPoint) {
        guard let panel else { return }
        collapseTask?.cancel()
        collapseTask = nil
        frameTransitionID += 1
        isApplyingFrame = false
        switch placement {
        case .docked:
            setEdgeReleaseProgress(FloatingPanelDragMotion.dockedEdgeReleaseProgress, animated: false)
            dragState = .pending(startMouse: mouseLocation, startFrame: panel.frame)
        case .detached:
            state.isDocked = false
            setEdgeReleaseProgress(FloatingPanelDragMotion.detachedEdgeReleaseProgress, animated: false)
            dragState = .active(startMouse: mouseLocation, startFrame: panel.frame)
        }
    }

    private func dragMoved(to mouseLocation: CGPoint) {
        guard let panel else { return }
        switch dragState {
        case .idle:
            return
        case let .pending(startMouse, startFrame):
            let step = FloatingPanelDragMotion.dragStep(
                startFrame: startFrame,
                startMouse: startMouse,
                currentMouse: mouseLocation,
                isDocked: true
            )
            guard case let .active(nextFrame, edgeReleaseProgress) = step else {
                return
            }
            placement = .detached(frame: nextFrame)
            state.isDocked = false
            setEdgeReleaseProgress(edgeReleaseProgress, animated: true)
            let frame = magneticFrame(for: nextFrame)
            placement = .detached(frame: frame)
            dragState = .active(startMouse: startMouse, startFrame: startFrame)
            panel.setFrame(frame, display: true)
        case let .active(startMouse, startFrame):
            let nextFrame = FloatingPanelDragMotion.frame(
                startFrame: startFrame,
                startMouse: startMouse,
                currentMouse: mouseLocation
            )
            let frame = magneticFrame(for: nextFrame)
            placement = .detached(frame: frame)
            panel.setFrame(frame, display: true)
        }
    }

    private func dragEnded(at mouseLocation: CGPoint) {
        guard let panel, let preferences else { return }
        let wasActive: Bool
        let releaseFrame: CGRect
        switch dragState {
        case .idle:
            return
        case .pending:
            wasActive = false
            releaseFrame = panel.frame
        case .active:
            wasActive = true
            releaseFrame = panel.frame
        }
        dragState = .idle

        guard wasActive else {
            updateHoverAfterDrag(mouseLocation: mouseLocation)
            if !isHovering {
                scheduleCollapse()
            }
            return
        }

        let screen = bestScreen(for: releaseFrame.center)
        switch FloatingPanelDragMotion.releasePlacement(for: releaseFrame, in: screen.visibleFrame) {
        case let .docked(edge, anchor):
            placement = .docked
            state.isDocked = true
            setEdgeReleaseProgress(FloatingPanelDragMotion.dockedEdgeReleaseProgress, animated: true)
            persistPlacement(edge: edge, anchor: anchor, preferences: preferences)
            applyStoredFrame(animated: true)
        case let .detached(frame):
            let detachedFrame = expandedDetachedFrame(from: frame, in: screen.visibleFrame)
            placement = .detached(frame: detachedFrame)
            state.isDocked = false
            setEdgeReleaseProgress(FloatingPanelDragMotion.detachedEdgeReleaseProgress, animated: false)
            state.isExpanded = true
            if !panel.frame.isApproximatelyEqual(to: detachedFrame) {
                panel.setFrame(detachedFrame, display: true)
            }

            updateHoverAfterDrag(mouseLocation: mouseLocation)
            if !isHovering {
                scheduleCollapse()
            }
        }
    }

    private func persistPlacement(edge: FloatingPanelEdge, anchor: Double, preferences: Preferences) {
        state.edge = edge
        suppressPreferenceSync = true
        preferences.floatingTabEdge = edge
        preferences.floatingTabAnchor = anchor
        DispatchQueue.main.async { [weak self] in
            self?.suppressPreferenceSync = false
        }
    }

    private func updateHoverAfterDrag(mouseLocation: CGPoint) {
        isHovering = panel?.frame.contains(mouseLocation) ?? false
    }

    private func applyStoredFrame(animated: Bool) {
        guard let panel, let preferences else { return }
        guard !dragState.isDragging else { return }
        guard placement.isDocked else { return }
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

        state.edge = preferences.floatingTabEdge
        state.isDocked = true
        setEdgeReleaseProgress(FloatingPanelDragMotion.dockedEdgeReleaseProgress, animated: animated)
        if animated {
            setPanelFrame(frame, animated: true)
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
                self?.applyCurrentPlacementAfterScreenChange(animated: true)
            }
        }
    }

    private func collapseCurrentPlacement(animated: Bool) {
        switch placement {
        case .docked:
            setExpanded(false, animated: animated)
        case .detached:
            dockDetachedPanel(animated: animated)
        }
    }

    private func dockDetachedPanel(animated: Bool) {
        guard let panel, let preferences else { return }
        let screen = bestScreen(for: panel.frame.center)
        let edge = FloatingPanelGeometry.nearestEdge(to: panel.frame.center, in: screen.visibleFrame)
        let size = FloatingPanelGeometry.size(edge: edge, expanded: false)
        let anchor = FloatingPanelGeometry.anchor(for: panel.frame.center, edge: edge, in: screen.visibleFrame, size: size)

        placement = .docked
        state.isDocked = true
        state.isExpanded = false
        setEdgeReleaseProgress(FloatingPanelDragMotion.dockedEdgeReleaseProgress, animated: animated)
        persistPlacement(edge: edge, anchor: anchor, preferences: preferences)
        applyStoredFrame(animated: animated)
    }

    private func applyCurrentPlacementAfterScreenChange(animated: Bool) {
        guard let panel else { return }
        guard !dragState.isDragging else { return }
        switch placement {
        case .docked:
            applyStoredFrame(animated: animated)
        case .detached:
            let screen = bestScreen(for: panel.frame.center)
            let frame = FloatingPanelDragMotion.clampedFrame(panel.frame, in: screen.visibleFrame)
            placement = .detached(frame: frame)
            setPanelFrame(frame, animated: animated)
        }
    }

    private func magneticFrame(for frame: CGRect) -> CGRect {
        let screen = bestScreen(for: frame.center)
        return FloatingPanelDragMotion.magneticFrame(frame, in: screen.visibleFrame)
    }

    private func expandedDetachedFrame(from frame: CGRect, in visibleFrame: CGRect) -> CGRect {
        guard !state.isExpanded else {
            return FloatingPanelDragMotion.clampedFrame(frame, in: visibleFrame)
        }

        let expandedSize = FloatingPanelGeometry.expandedSize
        let expandedFrame = CGRect(
            x: frame.midX - expandedSize.width / 2,
            y: frame.midY - expandedSize.height / 2,
            width: expandedSize.width,
            height: expandedSize.height
        )
        return FloatingPanelDragMotion.clampedFrame(expandedFrame, in: visibleFrame)
    }

    private func setEdgeReleaseProgress(_ progress: CGFloat, animated: Bool) {
        let clamped = min(max(progress, 0), 1)
        guard state.edgeReleaseProgress != clamped else { return }
        if animated {
            withAnimation(.easeOut(duration: 0.14)) {
                state.edgeReleaseProgress = clamped
            }
        } else {
            state.edgeReleaseProgress = clamped
        }
    }

    private func setPanelFrame(_ frame: CGRect, animated: Bool) {
        guard let panel else { return }
        guard animated else {
            panel.setFrame(frame, display: true)
            return
        }

        frameTransitionID += 1
        let transitionID = frameTransitionID
        isApplyingFrame = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.allowsImplicitAnimation = true
            panel.animator().setFrame(frame, display: true)
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                self?.finishFrameTransition(id: transitionID)
            }
        }
    }

    private func finishFrameTransition(id: Int) {
        guard id == frameTransitionID else { return }
        isApplyingFrame = false
        refreshHoverStateAfterFrameChange()
    }

    private func refreshHoverStateAfterFrameChange() {
        guard !dragState.isDragging else { return }
        if isMouseInsidePanel() {
            isHovering = true
            collapseTask?.cancel()
            collapseTask = nil
        } else {
            isHovering = false
            if state.isExpanded {
                scheduleCollapse()
            }
        }
    }

    private func isMouseInsidePanel() -> Bool {
        panel?.frame.contains(NSEvent.mouseLocation) ?? false
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

    func isApproximatelyEqual(to other: CGRect, tolerance: CGFloat = 0.5) -> Bool {
        abs(origin.x - other.origin.x) <= tolerance
            && abs(origin.y - other.origin.y) <= tolerance
            && abs(size.width - other.size.width) <= tolerance
            && abs(size.height - other.size.height) <= tolerance
    }
}
