import AppKit
import SwiftUI

/// Standard content scroll container for the app.
///
/// Use this for full content regions such as sidebars, detail panes, lists,
/// settings, and inspectors. It intentionally delegates indicator rendering and
/// hiding behavior to the native macOS scroll view instead of drawing custom
/// scrollbar chrome.
struct AppScrollView<Content: View>: View {
    private let axes: Axis.Set
    private let content: () -> Content

    init(_ axes: Axis.Set = .vertical, @ViewBuilder content: @escaping () -> Content) {
        self.axes = axes
        self.content = content
    }

    var body: some View {
        ScrollView(axes) {
            content()
        }
        .scrollIndicators(.automatic)
    }
}

enum AppScrollbars {
    @MainActor
    static func configure(_ scrollView: NSScrollView, axes: Axis.Set = .vertical) {
        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = true
        scrollView.hasVerticalScroller = axes.contains(.vertical)
        scrollView.hasHorizontalScroller = axes.contains(.horizontal)
    }
}
