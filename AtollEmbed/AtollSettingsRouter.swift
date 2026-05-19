import Foundation

@MainActor
public enum AtollSettingsRouter {
    public static var openSettings: (() -> Void)?

    static func openNotchIslandSettings() {
        openSettings?()
    }
}
