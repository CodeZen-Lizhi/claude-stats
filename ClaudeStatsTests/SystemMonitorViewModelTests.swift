import Foundation
import Testing
@testable import ClaudeStats

@MainActor
struct SystemMonitorViewModelTests {
    @Test("Manual refresh appends snapshots and respects history limit")
    func manualRefreshAppendsSnapshots() async {
        let sampler = CountingSystemMonitorSampler()
        let vm = SystemMonitorViewModel(sampler: sampler, historyLimit: 2)

        await vm.refreshNow()
        await vm.refreshNow()
        await vm.refreshNow()

        #expect(vm.snapshot?.timestamp == Date(timeIntervalSince1970: 3))
        #expect(vm.history.map(\.timestamp) == [
            Date(timeIntervalSince1970: 2),
            Date(timeIntervalSince1970: 3),
        ])
        #expect(await sampler.sampleCount == 3)
    }

    @Test("Off refresh rate does not start automatic sampling")
    func offRefreshRateDoesNotStartAutomaticSampling() async throws {
        let sampler = CountingSystemMonitorSampler()
        let vm = SystemMonitorViewModel(sampler: sampler, historyLimit: 4)

        vm.start(refreshRate: .off)
        try await Task.sleep(for: .milliseconds(50))

        #expect(vm.isRunning == false)
        #expect(vm.snapshot == nil)
        #expect(await sampler.sampleCount == 0)
    }

    @Test("Start and stop update running state")
    func startAndStopUpdateRunningState() {
        let sampler = CountingSystemMonitorSampler()
        let vm = SystemMonitorViewModel(sampler: sampler, historyLimit: 4)

        vm.start(refreshRate: .oneSecond)
        #expect(vm.isRunning)

        vm.stop()
        #expect(!vm.isRunning)
    }
}

private actor CountingSystemMonitorSampler: SystemMonitorSampling {
    private(set) var sampleCount = 0

    func sample() async -> SystemMonitorSnapshot {
        sampleCount += 1
        return Self.snapshot(index: sampleCount)
    }

    private static func snapshot(index: Int) -> SystemMonitorSnapshot {
        SystemMonitorSnapshot(
            timestamp: Date(timeIntervalSince1970: TimeInterval(index)),
            cpu: SystemCPUSnapshot(
                totalUsage: 0.1,
                userUsage: 0.07,
                systemUsage: 0.03,
                idleUsage: 0.9,
                perCoreUsage: [0.1, 0.2]
            ),
            memory: .placeholder,
            disk: .placeholder,
            network: .placeholder,
            battery: .placeholder,
            gpu: .unavailable,
            thermal: SystemThermalSnapshot(state: .nominal)
        )
    }
}
