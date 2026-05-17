import Foundation
import Observation

@MainActor
@Observable
final class SystemMonitorViewModel {
    private(set) var snapshot: SystemMonitorSnapshot?
    private(set) var history: [SystemMonitorSnapshot] = []
    private(set) var lastRefreshError: String?
    private(set) var isRunning = false

    @ObservationIgnored private let sampler: any SystemMonitorSampling
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private let historyLimit: Int

    init(
        sampler: any SystemMonitorSampling = SystemMonitorSampler(),
        historyLimit: Int = 100
    ) {
        self.sampler = sampler
        self.historyLimit = historyLimit
    }

    deinit {
        refreshTask?.cancel()
    }

    func start(refreshRate: SystemMonitorRefreshRate) {
        stop()
        guard let interval = refreshRate.interval else {
            isRunning = false
            return
        }

        isRunning = true
        refreshTask = Task { [weak self] in
            await self?.refreshNow()
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: interval)
                } catch {
                    break
                }
                guard !Task.isCancelled else { break }
                await self?.refreshNow()
            }
        }
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
        isRunning = false
    }

    func refreshNow() async {
        let next = await sampler.sample()
        snapshot = next
        history = SystemMonitorMath.limitedHistory(history, appending: next, limit: historyLimit)
        lastRefreshError = nil
    }
}
