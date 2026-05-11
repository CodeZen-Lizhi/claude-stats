import SwiftUI
import AppKit

/// A vertical scroll view with a self-managed scroll indicator: invisible while
/// idle, it fades *in* when the user scrolls, lingers briefly, then fades *out*.
///
/// The system scroller is suppressed entirely (both the auto-hiding overlay one
/// and the permanent legacy one shown when "Show scroll bars" is set to
/// "Always"), and we draw our own thin indicator so the behaviour is consistent
/// regardless of system settings or whether the content is a `ScrollView` or a
/// `List`.
struct FadingScrollView<Content: View>: View {
    private let content: () -> Content
    @State private var model = ScrollIndicatorModel()

    private let coordinateSpace = "FadingScrollView"

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        ScrollView {
            content()
                .background(NativeScrollerSuppressor())
                .background(
                    GeometryReader { proxy in
                        Color.clear
                            .preference(key: ContentFrameKey.self,
                                        value: proxy.frame(in: .named(coordinateSpace)))
                            .allowsHitTesting(false)
                    }
                )
        }
        .scrollIndicators(.hidden)
        .coordinateSpace(.named(coordinateSpace))
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onChange(of: proxy.size.height, initial: true) { _, height in
                        model.viewportHeight = height
                    }
                    .allowsHitTesting(false)
            }
        )
        .onPreferenceChange(ContentFrameKey.self) { [model] frame in
            MainActor.assumeIsolated { model.contentFrameChanged(frame) }
        }
        .overlay(alignment: .topTrailing) { ScrollThumb(model: model) }
    }
}

// MARK: - Custom indicator

private struct ScrollThumb: View {
    let model: ScrollIndicatorModel

    var body: some View {
        let overflow = model.contentHeight - model.viewportHeight
        if overflow > 1, model.viewportHeight > 1 {
            let track = model.viewportHeight
            let thumbHeight = min(track, max(28, track * (model.viewportHeight / model.contentHeight)))
            let progress = min(max(model.offset / overflow, 0), 1)
            Capsule()
                .fill(Color.primary.opacity(0.32))
                .frame(width: 4, height: thumbHeight)
                .padding(.trailing, 2.5)
                .offset(y: (track - thumbHeight) * progress)
                .opacity(model.indicatorShown ? 1 : 0)
                .allowsHitTesting(false)
        }
    }
}

@MainActor
@Observable
private final class ScrollIndicatorModel {
    var contentHeight: CGFloat = 0
    var viewportHeight: CGFloat = 0
    var offset: CGFloat = 0
    var indicatorShown = false

    @ObservationIgnored private var hideTask: Task<Void, Never>?

    func contentFrameChanged(_ frame: CGRect) {
        contentHeight = frame.height
        let newOffset = -frame.minY
        if abs(newOffset - offset) > 0.5 { flash() }
        offset = newOffset
    }

    private func flash() {
        hideTask?.cancel()
        if !indicatorShown {
            withAnimation(.easeOut(duration: 0.22)) { indicatorShown = true }
        }
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.1))
            guard let self, !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.55)) { self.indicatorShown = false }
        }
    }
}

private struct ContentFrameKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

// MARK: - System scroller removal

/// A zero-size, non-interactive `NSView` hosted inside the SwiftUI scroll view's
/// content. Once attached it walks up to the enclosing `NSScrollView` and turns
/// off its scrollers, re-asserting whenever the view scrolls or relays out
/// (SwiftUI re-enables them behind our back otherwise).
private struct NativeScrollerSuppressor: NSViewRepresentable {
    func makeNSView(context: Context) -> SuppressorView { SuppressorView() }
    func updateNSView(_ nsView: SuppressorView, context: Context) { nsView.suppress() }

    final class SuppressorView: NSView {
        private nonisolated(unsafe) var observation: NSObjectProtocol?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            suppress()
            // SwiftUI realizes its scroll view a touch after this background, so
            // re-run once the current run-loop turn is done as well.
            perform(#selector(suppress), with: nil, afterDelay: 0)
            startObservingScroll()
        }

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            suppress()
            startObservingScroll()
        }

        override func layout() {
            super.layout()
            suppress()
        }

        deinit {
            if let observation { NotificationCenter.default.removeObserver(observation) }
        }

        private func startObservingScroll() {
            guard observation == nil, let clipView = targetScrollView?.contentView else { return }
            clipView.postsBoundsChangedNotifications = true
            observation = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: clipView,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.suppress() }
            }
        }

        private var targetScrollView: NSScrollView? {
            var view: NSView? = self
            while let current = view {
                if let scrollView = current as? NSScrollView { return scrollView }
                if let scrollView = current.enclosingScrollView { return scrollView }
                view = current.superview
            }
            return nil
        }

        @objc func suppress() {
            guard let scrollView = targetScrollView else { return }
            scrollView.scrollerStyle = .overlay
            scrollView.autohidesScrollers = true
            scrollView.hasVerticalScroller = false
            scrollView.hasHorizontalScroller = false
        }
    }
}
