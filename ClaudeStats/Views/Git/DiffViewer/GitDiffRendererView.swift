import AppKit
import SwiftUI

struct GitDiffRendererView: NSViewRepresentable {
    let diff: StructuredFileDiff
    let mode: DiffViewMode
    let granularity: GitDiffBlockGranularity

    func makeNSView(context: Context) -> GitDiffScrollContainerView {
        let container = GitDiffScrollContainerView()
        container.update(diff: diff, mode: mode, granularity: granularity)
        return container
    }

    func updateNSView(_ container: GitDiffScrollContainerView, context: Context) {
        container.update(diff: diff, mode: mode, granularity: granularity)
    }
}

@MainActor
final class GitDiffScrollContainerView: NSView {
    private let scrollView = NSScrollView()
    private let documentView = GitDiffDocumentView()
    private let renderView = GitDiffRenderView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func update(diff: StructuredFileDiff, mode: DiffViewMode, granularity: GitDiffBlockGranularity) {
        renderView.update(diff: diff, mode: mode, granularity: granularity)
        updateDocumentSize()
        synchronizeRenderer()
    }

    override func layout() {
        super.layout()
        scrollView.frame = bounds
        updateDocumentSize()
        synchronizeRenderer()
    }

    private func configure() {
        self.scrollView.borderType = .noBorder
        self.scrollView.drawsBackground = false
        self.scrollView.hasHorizontalScroller = false
        self.scrollView.allowsMagnification = false
        self.scrollView.usesPredominantAxisScrolling = true
        AppScrollbars.configure(self.scrollView)

        documentView.frame = .zero
        documentView.postsFrameChangedNotifications = false
        renderView.contentHeightDidChange = { [weak self] in
            self?.updateDocumentSize()
            self?.synchronizeRenderer()
        }
        documentView.addSubview(renderView)

        let clipView = GitDiffClipView()
        clipView.postsBoundsChangedNotifications = true
        clipView.setValue(false, forKey: "copiesOnScroll")

        self.scrollView.contentView = clipView
        self.scrollView.documentView = documentView
        addSubview(self.scrollView)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(clipBoundsDidChange(_:)),
            name: NSView.boundsDidChangeNotification,
            object: self.scrollView.contentView
        )
    }

    private func updateDocumentSize() {
        let viewport = scrollView.contentView.bounds
        let width = max(viewport.width, bounds.width, 1)
        let height = max(renderView.contentHeight, viewport.height + 1, 1)
        if documentView.frame.size != NSSize(width: width, height: height) {
            documentView.setFrameSize(NSSize(width: width, height: height))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }

    private func synchronizeRenderer() {
        let visible = scrollView.contentView.documentVisibleRect
        guard visible.width > 0, visible.height > 0 else { return }
        let rendererFrame = CGRect(origin: visible.origin, size: visible.size)
        if renderView.frame != rendererFrame {
            renderView.frame = rendererFrame
        }
        renderView.updateViewport(scrollY: visible.minY, size: visible.size)
    }

    @objc private func clipBoundsDidChange(_ notification: Notification) {
        synchronizeRenderer()
    }
}

@MainActor
private final class GitDiffClipView: NSClipView {
    override var bounds: NSRect {
        didSet {
            guard bounds != oldValue else { return }
            documentView?.setNeedsDisplay(bounds.union(oldValue))
        }
    }
}

private final class GitDiffDocumentView: NSView {
    override var isFlipped: Bool { true }
}
