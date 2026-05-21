import SwiftUI
import PhosphorSwift

public struct FunctionalLabel: View {
    private let title: Text
    private let icon: FunctionalIcon
    private let size: CGFloat
    private let color: Color?
    private let weight: Ph.IconWeight

    public init(
        _ titleKey: LocalizedStringKey,
        icon: FunctionalIcon,
        size: CGFloat = 15,
        color: Color? = nil,
        weight: Ph.IconWeight = .duotone
    ) {
        self.title = Text(titleKey)
        self.icon = icon
        self.size = size
        self.color = color
        self.weight = weight
    }

    public init(
        _ title: String,
        icon: FunctionalIcon,
        size: CGFloat = 15,
        color: Color? = nil,
        weight: Ph.IconWeight = .duotone
    ) {
        self.title = Text(title)
        self.icon = icon
        self.size = size
        self.color = color
        self.weight = weight
    }

    public init(
        _ titleKey: LocalizedStringKey,
        systemSymbolName: String,
        size: CGFloat = 15,
        color: Color? = nil,
        weight: Ph.IconWeight = .duotone
    ) {
        self.init(
            titleKey,
            icon: FunctionalIcon.fromSystemName(systemSymbolName),
            size: size,
            color: color,
            weight: weight
        )
    }

    public init(
        _ title: String,
        systemSymbolName: String,
        size: CGFloat = 15,
        color: Color? = nil,
        weight: Ph.IconWeight = .duotone
    ) {
        self.init(
            title,
            icon: FunctionalIcon.fromSystemName(systemSymbolName),
            size: size,
            color: color,
            weight: weight
        )
    }

    public var body: some View {
        Label {
            title
        } icon: {
            FunctionalIconView(icon: icon, size: size, color: color, weight: weight)
        }
    }
}
