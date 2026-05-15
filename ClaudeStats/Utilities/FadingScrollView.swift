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
    enum Chrome {
        case fading
        case plain
    }

    private let chrome: Chrome
    private let content: () -> Content
    @State private var model = ScrollIndicatorModel()
    @State private var coordinateSpaceName = UUID()

    init(chrome: Chrome = .fading, @ViewBuilder content: @escaping () -> Content) {
        self.chrome = chrome
        self.content = content
    }

    @ViewBuilder
    var body: some View {
        switch chrome {
        case .fading:
            fadingBody
        case .plain:
            plainBody
        }
    }

    private var plainBody: some View {
        ScrollView {
            content()
        }
    }

    private var fadingBody: some View {
        ScrollView {
            content()
                .background(NativeScrollerSuppressor())
                .background(
                    GeometryReader { proxy in
                        Color.clear
                            .preference(
                                key: ContentFrameKey.self,
                                value: ContentFrameMetrics(frame: proxy.frame(in: .named(coordinateSpaceName)))
                            )
                            .allowsHitTesting(false)
                    }
                )
        }
        .scrollIndicators(.hidden)
        .coordinateSpace(.named(coordinateSpaceName))
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onChange(of: proxy.size.height, initial: true) { _, height in
                        // Sub-pixel layout passes during a resize can ripple
                        // updates through the indicator subtree even when the
                        // value hasn't meaningfully changed. Clamp to 0.5pt.
                        if abs(height - model.viewportHeight) > 0.5 {
                            model.viewportHeight = height
                        }
                    }
                    .allowsHitTesting(false)
            }
        )
        .onPreferenceChange(ContentFrameKey.self) { [model] metrics in
            MainActor.assumeIsolated { model.contentFrameChanged(metrics) }
        }
        .mask { EdgeFadeMask(model: model) }
        .overlay(alignment: .topTrailing) { ScrollThumb(model: model) }
    }
}

// MARK: - Soft edge fade

/// A `mask` view that keeps the scroll content fully opaque except for a short
/// gradient band at whichever edge can still be scrolled — so content slides
/// under the surrounding chrome with a soft fade instead of a hard clip. The
/// band collapses to nothing when an edge is at its travel limit.
private struct EdgeFadeMask: View {
    let model: ScrollIndicatorModel
    private let band: CGFloat = 20

    var body: some View {
        let overflow = max(model.contentHeight - model.viewportHeight, 0)
        let topFade = min(max(model.offset, 0), band)
        let bottomFade = min(max(overflow - model.offset, 0), band)
        VStack(spacing: 0) {
            LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                .frame(height: topFade)
            Color.black
            LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: bottomFade)
        }
    }
}

// MARK: - Custom indicator

private struct ScrollThumb: View {
    let model: ScrollIndicatorModel
    private let verticalInset: CGFloat = 10

    var body: some View {
        let overflow = model.contentHeight - model.viewportHeight
        if overflow > 1, model.viewportHeight > 1 {
            let inset = min(verticalInset, model.viewportHeight / 3)
            let track = max(model.viewportHeight - inset * 2, 1)
            let thumbHeight = min(track, max(28, track * (model.viewportHeight / model.contentHeight)))
            let progress = min(max(model.offset / overflow, 0), 1)
            Capsule()
                .fill(Color.primary.opacity(0.32))
                .frame(width: 4, height: thumbHeight)
                .padding(.trailing, 2.5)
                .offset(y: inset + (track - thumbHeight) * progress)
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

    func contentFrameChanged(_ metrics: ContentFrameMetrics) {
        if abs(metrics.contentHeight - contentHeight) > 0.5 {
            contentHeight = metrics.contentHeight
        }
        if abs(metrics.offsetY - offset) > 0.5 {
            offset = metrics.offsetY
            flash()
        }
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

private struct ContentFrameMetrics: Equatable {
    var contentHeight: CGFloat
    var offsetY: CGFloat

    static let zero = ContentFrameMetrics(contentHeight: 0, offsetY: 0)

    init(contentHeight: CGFloat, offsetY: CGFloat) {
        self.contentHeight = contentHeight
        self.offsetY = offsetY
    }

    init(frame: CGRect) {
        contentHeight = frame.height
        offsetY = -frame.minY
    }
}

private struct ContentFrameKey: PreferenceKey {
    static let defaultValue: ContentFrameMetrics = .zero
    static func reduce(value: inout ContentFrameMetrics, nextValue: () -> ContentFrameMetrics) {
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
            // `layout()` runs unbounded times during a resize. Skip the AppKit
            // writes when the scroll view is already in the desired state so
            // the per-layout cost is just four property reads.
            if scrollView.scrollerStyle == .overlay,
               scrollView.autohidesScrollers,
               !scrollView.hasVerticalScroller,
               !scrollView.hasHorizontalScroller {
                return
            }
            scrollView.scrollerStyle = .overlay
            scrollView.autohidesScrollers = true
            scrollView.hasVerticalScroller = false
            scrollView.hasHorizontalScroller = false
        }
    }
}
