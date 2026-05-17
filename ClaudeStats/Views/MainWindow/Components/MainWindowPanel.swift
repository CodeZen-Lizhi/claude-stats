import SwiftUI

extension View {
    /// Shared main-window panel chrome: the same rounded card treatment used by
    /// wide Dashboard/Usage-style pages.
    func mainWindowPanel(padding: CGFloat = 14) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.stxPanel, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.stxStroke, lineWidth: 1))
    }
}
