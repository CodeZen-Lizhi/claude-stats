import SwiftUI

/// The main window's detail area. Sits flush with the window's top, right,
/// and bottom edges; only its left side (where it meets the vibrancy sidebar)
/// is rounded. The opaque `Color.stxBackground` fill against the translucent
/// sidebar gives it the "above the sidebar in z-index" reading — the sidebar
/// vibrancy peeks through the rounded corner cutouts on the left.
struct DetailPanel<Content: View>: View {
    var roundedLeading: Bool = true
    @ViewBuilder var content: () -> Content

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: roundedLeading ? 12 : 0,
            bottomLeadingRadius: roundedLeading ? 12 : 0,
            bottomTrailingRadius: 0,
            topTrailingRadius: 0
        )
    }

    var body: some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.stxBackground, in: shape)
    }
}
