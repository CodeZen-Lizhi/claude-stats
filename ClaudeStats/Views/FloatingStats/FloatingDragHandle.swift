import AppKit
import SwiftUI

struct FloatingDragHandle: NSViewRepresentable {
    var onHoverChanged: (Bool) -> Void
    var onDragBegan: (CGPoint) -> Void
    var onDragMoved: (CGPoint) -> Void
    var onDragEnded: (CGPoint) -> Void

    func makeNSView(context: Context) -> HandleView {
        let view = HandleView()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ nsView: HandleView, context: Context) {
        nsView.onHoverChanged = onHoverChanged
        nsView.onDragBegan = onDragBegan
        nsView.onDragMoved = onDragMoved
        nsView.onDragEnded = onDragEnded
    }

    @MainActor
    final class HandleView: NSView {
        var onHoverChanged: (Bool) -> Void = { _ in }
        var onDragBegan: (CGPoint) -> Void = { _ in }
        var onDragMoved: (CGPoint) -> Void = { _ in }
        var onDragEnded: (CGPoint) -> Void = { _ in }

        private var trackingArea: NSTrackingArea?

        override var acceptsFirstResponder: Bool { true }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
            true
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let trackingArea {
                removeTrackingArea(trackingArea)
            }
            let area = NSTrackingArea(
                rect: bounds,
                options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
                owner: self
            )
            addTrackingArea(area)
            trackingArea = area
        }

        override func mouseEntered(with event: NSEvent) {
            onHoverChanged(true)
        }

        override func mouseExited(with event: NSEvent) {
            onHoverChanged(false)
        }

        override func mouseDown(with event: NSEvent) {
            onDragBegan(NSEvent.mouseLocation)
        }

        override func mouseDragged(with event: NSEvent) {
            onDragMoved(NSEvent.mouseLocation)
        }

        override func mouseUp(with event: NSEvent) {
            onDragEnded(NSEvent.mouseLocation)
        }
    }
}
