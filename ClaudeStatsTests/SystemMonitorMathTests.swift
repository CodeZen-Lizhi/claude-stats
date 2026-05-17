import Foundation
import Testing
@testable import ClaudeStats

struct SystemMonitorMathTests {
    @Test("CPU delta computes user system and idle ratios")
    func cpuDeltaComputesRatios() {
        let previous = SystemCPUCounter(user: 100, system: 100, nice: 0, idle: 800)
        let current = SystemCPUCounter(user: 150, system: 130, nice: 20, idle: 900)

        let load = SystemMonitorMath.cpuLoad(current: current, previous: previous)

        #expect(abs(load.user - 0.35) < 0.001)
        #expect(abs(load.system - 0.15) < 0.001)
        #expect(abs(load.idle - 0.50) < 0.001)
        #expect(abs(load.total - 0.50) < 0.001)
    }

    @Test("Byte rate drops negative deltas and divides by elapsed time")
    func byteRateHandlesCounters() {
        #expect(SystemMonitorMath.byteRate(current: 1_600, previous: 1_000, elapsed: 3) == 200)
        #expect(SystemMonitorMath.byteRate(current: 900, previous: 1_000, elapsed: 3) == 0)
        #expect(SystemMonitorMath.byteRate(current: 1_600, previous: nil, elapsed: 3) == 0)
        #expect(SystemMonitorMath.byteRate(current: 1_600, previous: 1_000, elapsed: 0) == 0)
    }

    @Test("History keeps newest values within limit")
    func historyLimitKeepsNewestValues() {
        var values: [Int] = []
        values = SystemMonitorMath.limitedHistory(values, appending: 1, limit: 3)
        values = SystemMonitorMath.limitedHistory(values, appending: 2, limit: 3)
        values = SystemMonitorMath.limitedHistory(values, appending: 3, limit: 3)
        values = SystemMonitorMath.limitedHistory(values, appending: 4, limit: 3)

        #expect(values == [2, 3, 4])
    }
}
