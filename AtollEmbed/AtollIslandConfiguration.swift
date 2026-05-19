import CoreGraphics
import Foundation

public enum AtollIslandFeature: String, CaseIterable, Sendable {
    case media
    case stats
    case timer
    case clipboard
    case colorPicker
    case calendar
    case shelf
    case privacy
    case recording
    case focus
    case battery
    case bluetooth
    case downloads
    case osd
    case lockScreenWidgets
    case extensionBridge
    case screenAssistant
    case terminal
}

public struct AtollIslandConfiguration: Sendable, Equatable {
    public var enabledFeatures: Set<AtollIslandFeature>
    public var openNotchWidth: CGFloat
    public var openOnHover: Bool
    public var showOnAllDisplays: Bool
    public var statsUpdateInterval: TimeInterval

    public init(
        enabledFeatures: Set<AtollIslandFeature>,
        openNotchWidth: CGFloat,
        openOnHover: Bool,
        showOnAllDisplays: Bool,
        statsUpdateInterval: TimeInterval
    ) {
        self.enabledFeatures = enabledFeatures
        self.openNotchWidth = openNotchWidth
        self.openOnHover = openOnHover
        self.showOnAllDisplays = showOnAllDisplays
        self.statsUpdateInterval = statsUpdateInterval
    }
}
