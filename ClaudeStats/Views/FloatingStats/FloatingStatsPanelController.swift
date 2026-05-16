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

    private weak var environment: AppEnvironment?
    private weak var preferences: Preferences?
    private let state = FloatingStatsPanelState()

    private var panel: NSPanel?
    private var dragState: DragState = .idle
    private var collapseTask: Task<Void, Never>?
    private var screenObserver: NSObjectProtocol?
    private var suppressPreferenceSync = false
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
        dragState = .idle
        isHovering = false
        state.isExpanded = false
    }

    private func setHovering(_ hovering: Bool) {
        guard !dragState.isDragging else { return }
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
                self.setExpanded(false, animated: true)
            }
        }
    }

    private func setExpanded(_ expanded: Bool, animated: Bool) {
        guard state.isExpanded != expanded else { return }
        state.isExpanded = expanded
        applyStoredFrame(animated: animated)
    }

    private func dragBegan(at mouseLocation: CGPoint) {
        guard let panel else { return }
        collapseTask?.cancel()
        collapseTask = nil
        dragState = .pending(startMouse: mouseLocation, startFrame: panel.frame)
    }

    private func dragMoved(to mouseLocation: CGPoint) {
        guard let panel else { return }
        switch dragState {
        case .idle:
            return
        case let .pending(startMouse, startFrame):
            guard let nextFrame = FloatingPanelDragMotion.activatedFrame(
                startFrame: startFrame,
                startMouse: startMouse,
                currentMouse: mouseLocation
            ) else {
                return
            }
            dragState = .active(startMouse: startMouse, startFrame: startFrame)
            panel.setFrame(nextFrame, display: true)
        case let .active(startMouse, startFrame):
            let nextFrame = FloatingPanelDragMotion.frame(
                startFrame: startFrame,
                startMouse: startMouse,
                currentMouse: mouseLocation
            )
            panel.setFrame(nextFrame, display: true)
        }
    }

    private func dragEnded(at mouseLocation: CGPoint) {
        guard let panel, let preferences else { return }
        let wasActive: Bool
        switch dragState {
        case .idle:
            return
        case .pending:
            wasActive = false
        case let .active(startMouse, startFrame):
            wasActive = true
            let nextFrame = FloatingPanelDragMotion.frame(
                startFrame: startFrame,
                startMouse: startMouse,
                currentMouse: mouseLocation
            )
            panel.setFrame(nextFrame, display: true)
        }
        dragState = .idle

        guard wasActive else {
            updateHoverAfterDrag(mouseLocation: mouseLocation)
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

        persistPlacement(edge: edge, anchor: anchor, preferences: preferences)
        applyStoredFrame(animated: true)

        updateHoverAfterDrag(mouseLocation: mouseLocation)
        if !isHovering {
            scheduleCollapse()
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
