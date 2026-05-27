import Foundation
import Testing
@testable import ClaudeStats

@Suite("App lifecycle policy")
@MainActor
struct AppLifecyclePolicyTests {
    @Test("Resident menu bar app disables automatic termination")
    func residentMenuBarAppDisablesAutomaticTermination() {
        let processInfo = RecordingAutomaticTerminationController()

        AppLifecyclePolicy.configureAutomaticTermination(using: processInfo)

        #expect(processInfo.disableReasons == [AppLifecyclePolicy.automaticTerminationReason])
    }

    @Test("Resident menu bar app can reassert automatic termination policy after activation changes")
    func residentMenuBarAppCanReassertAutomaticTerminationPolicyAfterActivationChanges() {
        let processInfo = RecordingAutomaticTerminationController()

        AppLifecyclePolicy.configureAutomaticTermination(using: processInfo)
        AppLifecyclePolicy.reassertAutomaticTerminationPolicy()

        #expect(processInfo.disableReasons == [
            AppLifecyclePolicy.automaticTerminationReason,
            AppLifecyclePolicy.automaticTerminationReason,
        ])
    }
}

private final class RecordingAutomaticTerminationController: AutomaticTerminationControlling {
    private(set) var disableReasons: [String] = []

    func disableAutomaticTermination(_ reason: String) {
        disableReasons.append(reason)
    }
}
