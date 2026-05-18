import Foundation
import Testing
@testable import ClaudeStats

@Suite("NotchIslandRuntime")
@MainActor
struct NotchIslandRuntimeTests {
    @Test("Runtime keeps selected module inside enabled module list")
    func selectedModuleStaysEnabled() {
        let runtime = NotchIslandRuntime(sampler: StubSystemMonitorSampler())
        runtime.selectedModule = .media

        runtime.configure(enabledModules: [.timer, .clipboard], statsRefreshRate: .off)

        #expect(runtime.enabledModules == [.timer, .clipboard])
        #expect(runtime.selectedModule == .timer)
        runtime.stopAll()
    }

    @Test("Runtime falls back to safe modules when configured empty")
    func emptyModulesFallBack() {
        let runtime = NotchIslandRuntime(sampler: StubSystemMonitorSampler())

        runtime.configure(enabledModules: [], statsRefreshRate: .off)

        #expect(Set(runtime.enabledModules) == NotchIslandModule.defaultEnabled)
        runtime.stopAll()
    }

    @Test("Timer presets clamp to at least one minute")
    func timerPresetClamps() {
        let runtime = NotchIslandRuntime(sampler: StubSystemMonitorSampler())

        runtime.setTimer(minutes: 0)

        #expect(runtime.timerDurationSeconds == 60)
        #expect(runtime.timerRemainingSeconds == 60)
        runtime.stopAll()
    }
}

private actor StubSystemMonitorSampler: SystemMonitorSampling {
    func sample() async -> SystemMonitorSnapshot {
        .placeholder
    }
}
