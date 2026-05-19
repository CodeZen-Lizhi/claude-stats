import AppKit

@MainActor
final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    func showWindow() {
        AtollSettingsRouter.openNotchIslandSettings()
    }

    override func showWindow(_ sender: Any?) {
        AtollSettingsRouter.openNotchIslandSettings()
    }
}
