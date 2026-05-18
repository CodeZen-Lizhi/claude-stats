import Testing
@testable import ClaudeStats

@Suite("Updater Controller")
@MainActor
struct UpdaterControllerTests {
    @Test("Delegated gentle reminder keeps update pill visible after session ends")
    func delegatedGentleReminderPersistsAfterSession() {
        let updater = UpdaterController()

        updater.markUpdateAvailable(version: "1.4.7")
        updater.keepUpdateAvailabilityAfterCurrentSession()
        updater.finishUpdateSession()

        #expect(updater.updateAvailable == true)
        #expect(updater.availableUpdateVersion == "1.4.7")
    }

    @Test("Normal session finish clears update pill")
    func normalSessionFinishClearsAvailability() {
        let updater = UpdaterController()

        updater.markUpdateAvailable(version: "1.4.7")
        updater.finishUpdateSession()

        #expect(updater.updateAvailable == false)
        #expect(updater.availableUpdateVersion == nil)
    }
}
