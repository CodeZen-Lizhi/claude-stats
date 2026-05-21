import SwiftUI
import PhosphorSwift

public struct FunctionalIconView: View {
    public let icon: FunctionalIcon
    public var size: CGFloat
    public var color: Color?
    public var weight: Ph.IconWeight

    public init(
        icon: FunctionalIcon,
        size: CGFloat = 15,
        color: Color? = nil,
        weight: Ph.IconWeight = .duotone
    ) {
        self.icon = icon
        self.size = size
        self.color = color
        self.weight = weight
    }

    public init(
        systemSymbolName: String,
        size: CGFloat = 15,
        color: Color? = nil,
        weight: Ph.IconWeight = .duotone
    ) {
        self.init(
            icon: FunctionalIcon.fromSystemName(systemSymbolName),
            size: size,
            color: color,
            weight: weight
        )
    }

    public var body: some View {
        icon.phosphor.weight(weight)
            .renderingMode(.template)
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .modifier(FunctionalIconColorModifier(color: color))
            .accessibilityHidden(true)
    }
}

private struct FunctionalIconColorModifier: ViewModifier {
    let color: Color?

    func body(content: Content) -> some View {
        if let color {
            content.foregroundStyle(color)
        } else {
            content
        }
    }
}
