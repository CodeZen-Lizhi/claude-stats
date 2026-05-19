import AppKit
import Observation
import QuartzCore
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

    private enum FrameAnimationStyle {
        case standard
        case collapse

        var duration: TimeInterval {
            switch self {
            case .standard:
                FloatingStatsContentAnimation.panelExpandDuration
            case .collapse:
                FloatingStatsContentAnimation.panelCollapseDuration
            }
        }

        var timingFunction: CAMediaTimingFunction {
            switch self {
            case .standard:
                CAMediaTimingFunction(controlPoints: 0.22, 1.0, 0.36, 1.0)
            case .collapse:
                CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
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
    private var contentTransitionID = 0
    private var contentTransitionTask: Task<Void, Never>?
    private var isApplyingFrame = false
    private var isStarted = false
    private var isHovering = false
    private var requiresExitBeforeReexpand = false

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

        let hostingView = NSHostingView(rootView: rootView)
        hostingView.wantsLayer = true
        hostingView.layer?.isOpaque = false
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hostingView
        self.panel = panel
        panel.orderFrontRegardless()
    }

    private func closePanel() {
        collapseTask?.cancel()
        collapseTask = nil
        cancelContentTransition()
        panel?.orderOut(nil)
        panel = nil
        placement = .docked
        dragState = .idle
        frameTransitionID += 1
        isApplyingFrame = false
        isHovering = false
        requiresExitBeforeReexpand = false
        state.isExpanded = false
        state.expandedContentPhase = .hidden
        state.showsCollapsedContent = true
        state.isDocked = true
        setEdgeReleaseProgress(FloatingPanelDragMotion.dockedEdgeReleaseProgress, animated: false)
    }

    private func setHovering(_ hovering: Bool) {
        guard !dragState.isDragging else { return }
        guard !isApplyingFrame else { return }
        if requiresExitBeforeReexpand {
            if hovering || isMouseInsidePanel() {
                isHovering = false
                return
            }
            requiresExitBeforeReexpand = false
        }
        if !hovering, isMouseInsidePanel() {
            isHovering = true
            return
        }
        isHovering = hovering
        if hovering {
            requiresExitBeforeReexpand = false
            collapseTask?.cancel()
            collapseTask = nil
            setExpanded(true, animated: true)
        } else if state.isExpanded {
            scheduleCollapse()
        } else {
            collapseTask?.cancel()
            collapseTask = nil
        }
    }

    private func scheduleCollapse() {
        collapseTask?.cancel()
        collapseTask = nil
        guard !isHovering, !dragState.isDragging else { return }
        guard !isMouseInsidePanel() else {
            isHovering = true
            return
        }
        collapseCurrentPlacement(animated: true)
    }

    private func setExpanded(_ expanded: Bool, animated: Bool) {
        if expanded {
            requiresExitBeforeReexpand = false
            guard !state.isExpanded else {
                restoreExpandedContent(animated: animated)
                return
            }
            state.isExpanded = true
            prepareExpandedContentForReveal(animated: animated)
            applyStoredFrame(expanded: true, animated: animated, animationStyle: .standard)
            return
        }

        guard state.isExpanded else { return }
        if !placement.isDocked {
            dockDetachedPanel(animated: animated)
            return
        }
        collapseDockedPanel(animated: animated)
    }

    private func prepareExpandedContentForReveal(animated: Bool) {
        cancelContentTransition()
        state.showsCollapsedContent = false

        guard animated else {
            state.expandedContentPhase = .visible
            return
        }

        state.expandedContentPhase = .waitingToReveal
        contentTransitionID += 1
        let transitionID = contentTransitionID
        contentTransitionTask = Task { @MainActor [weak self] in
            try? await Task.sleep(
                nanoseconds: FloatingStatsContentAnimation.nanoseconds(for: FloatingStatsContentAnimation.revealInitialDelay)
            )
            guard let self, !Task.isCancelled, self.contentTransitionID == transitionID else { return }
            self.state.expandedContentPhase = .revealing

            try? await Task.sleep(
                nanoseconds: FloatingStatsContentAnimation.nanoseconds(for: FloatingStatsContentAnimation.totalRevealDuration)
            )
            guard !Task.isCancelled, self.contentTransitionID == transitionID else { return }
            self.state.expandedContentPhase = .visible
            self.contentTransitionTask = nil
        }
    }

    private func restoreExpandedContent(animated: Bool) {
        guard state.isExpanded else { return }
        cancelContentTransition()
        state.showsCollapsedContent = false
        switch state.expandedContentPhase {
        case .hidden, .waitingToReveal:
            prepareExpandedContentForReveal(animated: animated)
        case .revealing, .visible:
            break
        case .hiding:
            if animated {
                withAnimation(.easeOut(duration: FloatingStatsContentAnimation.collapseFadeDuration)) {
                    state.expandedContentPhase = .visible
                }
            } else {
                state.expandedContentPhase = .visible
            }
        }
    }

    private func cancelContentTransition() {
        contentTransitionTask?.cancel()
        contentTransitionTask = nil
        contentTransitionID += 1
    }

    private func dragBegan(at mouseLocation: CGPoint) {
        guard let panel else { return }
        collapseTask?.cancel()
        collapseTask = nil
        restoreExpandedContent(animated: false)
        frameTransitionID += 1
        isApplyingFrame = false
        requiresExitBeforeReexpand = false
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
            state.showsCollapsedContent = false
            state.expandedContentPhase = .visible
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
        applyStoredFrame(expanded: state.isExpanded, animated: animated)
    }

    private func applyStoredFrame(
        expanded: Bool,
        animated: Bool,
        animationStyle: FrameAnimationStyle = .standard,
        completion: (@MainActor @Sendable () -> Void)? = nil
    ) {
        guard let panel, let preferences else { return }
        guard !dragState.isDragging else { return }
        guard placement.isDocked else { return }
        let screen = bestScreen(for: panel.frame.center)
        let edge = preferences.floatingTabEdge
        let anchor = FloatingPanelGeometry.clampedAnchor(
            preferences.floatingTabAnchor,
            edge: edge,
            size: FloatingPanelGeometry.size(edge: edge, expanded: expanded),
            in: screen.visibleFrame
        )
        if anchor != preferences.floatingTabAnchor {
            preferences.floatingTabAnchor = anchor
        }
        let frame = FloatingPanelGeometry.frame(
            edge: edge,
            anchor: anchor,
            in: screen.visibleFrame,
            expanded: expanded
        )

        state.edge = edge
        state.isDocked = true
        setEdgeReleaseProgress(FloatingPanelDragMotion.dockedEdgeReleaseProgress, animated: animated)
        if animated {
            setPanelFrame(frame, animated: true, animationStyle: animationStyle, completion: completion)
        } else {
            panel.setFrame(frame, display: true)
            completion?()
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

    private func collapseDockedPanel(animated: Bool) {
        let finishCollapse: @MainActor @Sendable () -> Void = { [weak self] in
            guard let self else { return }
            self.showCollapsedContentForCollapsedFrame()
            self.updateHoverGateAfterDockedCollapse()
        }

        hideExpandedContentBeforePanelCollapse(animated: animated) { [weak self] in
            guard let self else { return }
            self.state.expandedContentPhase = .hidden
            self.state.showsCollapsedContent = false
            self.state.isExpanded = false
            self.applyStoredFrame(expanded: false, animated: animated, animationStyle: .collapse, completion: finishCollapse)
        }
    }

    private func hideExpandedContentBeforePanelCollapse(
        animated: Bool,
        completion: @escaping @MainActor @Sendable () -> Void
    ) {
        cancelContentTransition()
        guard animated, state.expandedContentPhase.mountsExpandedContent else {
            completion()
            return
        }

        contentTransitionID += 1
        let transitionID = contentTransitionID
        withAnimation(.easeOut(duration: FloatingStatsContentAnimation.collapseFadeDuration)) {
            state.expandedContentPhase = .hiding
        }

        contentTransitionTask = Task { @MainActor [weak self] in
            try? await Task.sleep(
                nanoseconds: FloatingStatsContentAnimation.nanoseconds(for: FloatingStatsContentAnimation.collapseFadeDuration)
            )
            guard let self, !Task.isCancelled, self.contentTransitionID == transitionID else { return }
            self.contentTransitionTask = nil
            completion()
        }
    }

    private func showCollapsedContentForCollapsedFrame() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            state.expandedContentPhase = .hidden
            state.showsCollapsedContent = true
        }
    }

    private func updateHoverGateAfterDockedCollapse() {
        collapseTask?.cancel()
        collapseTask = nil
        isHovering = false
        requiresExitBeforeReexpand = isMouseInsidePanel()
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
        state.expandedContentPhase = .hidden
        state.showsCollapsedContent = false
        setEdgeReleaseProgress(FloatingPanelDragMotion.dockedEdgeReleaseProgress, animated: animated)
        persistPlacement(edge: edge, anchor: anchor, preferences: preferences)
        applyStoredFrame(expanded: false, animated: animated, animationStyle: .collapse) { [weak self] in
            self?.showCollapsedContentForCollapsedFrame()
        }
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

    private func setPanelFrame(
        _ frame: CGRect,
        animated: Bool,
        animationStyle: FrameAnimationStyle = .standard,
        completion: (@MainActor @Sendable () -> Void)? = nil
    ) {
        guard let panel else { return }
        guard animated else {
            panel.setFrame(frame, display: true)
            completion?()
            return
        }

        frameTransitionID += 1
        let transitionID = frameTransitionID
        isApplyingFrame = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animationStyle.duration
            context.timingFunction = animationStyle.timingFunction
            context.allowsImplicitAnimation = true
            panel.animator().setFrame(frame, display: true)
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                self?.finishFrameTransition(id: transitionID, completion: completion)
            }
        }
    }

    private func finishFrameTransition(id: Int, completion: (@MainActor @Sendable () -> Void)? = nil) {
        guard id == frameTransitionID else { return }
        isApplyingFrame = false
        completion?()
        refreshHoverStateAfterFrameChange()
    }

    private func refreshHoverStateAfterFrameChange() {
        guard !dragState.isDragging else { return }
        if requiresExitBeforeReexpand {
            if isMouseInsidePanel() {
                isHovering = false
                collapseTask?.cancel()
                collapseTask = nil
                return
            }
            requiresExitBeforeReexpand = false
        }
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
