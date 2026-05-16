import AppKit
import SwiftUI

struct FloatingDragHandle: NSViewRepresentable {
    var onDragBegan: (CGPoint) -> Void
    var onDragMoved: (CGPoint) -> Void
    var onDragEnded: (CGPoint) -> Void

    func makeNSView(context: Context) -> HandleView {
        let view = HandleView()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ nsView: HandleView, context: Context) {
        nsView.onDragBegan = onDragBegan
        nsView.onDragMoved = onDragMoved
        nsView.onDragEnded = onDragEnded
    }

    @MainActor
    final class HandleView: NSView {
        var onDragBegan: (CGPoint) -> Void = { _ in }
        var onDragMoved: (CGPoint) -> Void = { _ in }
        var onDragEnded: (CGPoint) -> Void = { _ in }

        override var acceptsFirstResponder: Bool { true }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
            true
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
