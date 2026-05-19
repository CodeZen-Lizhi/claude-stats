import Testing
@testable import ClaudeStats

@Suite("NotchIslandController lifecycle")
@MainActor
struct NotchIslandControllerLifecycleTests {
    @Test("Disabled preferences start without creating island panels")
    func disabledPreferencesCreateNoPanels() {
        let env = AppEnvironment.preview(populated: false)
        env.preferences.notchIslandEnabled = false
        let controller = NotchIslandController()

        controller.start(environment: env)
        #expect(controller.activePanelCountForTesting == 0)

        controller.stop()
        #expect(controller.activePanelCountForTesting == 0)
    }
}
