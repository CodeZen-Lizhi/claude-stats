import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class NotchIslandRuntime {
    var selectedModule: NotchIslandModule = .stats
    var isExpanded = false
    private(set) var enabledModules: [NotchIslandModule] = NotchIslandModule.allCases.filter(NotchIslandModule.defaultEnabled.contains)
    private(set) var systemSnapshot: SystemMonitorSnapshot?
    private(set) var clipboardPreview = ""
    private(set) var selectedColorHex = "#7C5CFF"
    private(set) var activeStatusText = "Ready"

    private(set) var timerDurationSeconds = 5 * 60
    private(set) var timerRemainingSeconds = 5 * 60
    private(set) var timerRunning = false

    @ObservationIgnored private let sampler: any SystemMonitorSampling
    @ObservationIgnored private var statsTask: Task<Void, Never>?
    @ObservationIgnored private var timerTask: Task<Void, Never>?
    @ObservationIgnored private var activeStatsRefreshRate: SystemMonitorRefreshRate?

    init(sampler: any SystemMonitorSampling = SystemMonitorSampler()) {
        self.sampler = sampler
    }

    deinit {
        statsTask?.cancel()
        timerTask?.cancel()
    }

    func configure(enabledModules modules: Set<NotchIslandModule>, statsRefreshRate: SystemMonitorRefreshRate) {
        let ordered = NotchIslandModule.allCases.filter(modules.contains)
        enabledModules = ordered.isEmpty ? NotchIslandModule.allCases.filter(NotchIslandModule.defaultEnabled.contains) : ordered
        let activeModules = Set(enabledModules)
        if !enabledModules.contains(selectedModule) {
            selectedModule = enabledModules.first ?? .stats
        }

        if activeModules.contains(.stats) {
            startStats(refreshRate: statsRefreshRate == .off ? .threeSeconds : statsRefreshRate)
        } else {
            stopStats()
        }

        if activeModules.contains(.clipboard) {
            refreshClipboardPreview()
        }
    }

    func stopAll() {
        stopStats()
        stopTimer()
        isExpanded = false
    }

    func refreshStatsNow() {
        Task { [weak self] in
            guard let self else { return }
            let snapshot = await sampler.sample()
            await MainActor.run {
                self.systemSnapshot = snapshot
                self.activeStatusText = "Stats updated"
            }
        }
    }

    func refreshClipboardPreview() {
        let raw = NSPasteboard.general.string(forType: .string) ?? ""
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            clipboardPreview = "No text item"
        } else {
            clipboardPreview = String(trimmed.prefix(140))
        }
        activeStatusText = "Clipboard refreshed"
    }

    func openColorPanel() {
        let panel = NSColorPanel.shared
        panel.showsAlpha = true
        panel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        selectedColorHex = panel.color.hexString
        activeStatusText = "Color panel opened"
    }

    func setTimer(minutes: Int) {
        stopTimer()
        let clampedSeconds = max(60, min(max(1, minutes) * 60, 24 * 60 * 60))
        timerDurationSeconds = clampedSeconds
        timerRemainingSeconds = clampedSeconds
    }

    func startTimer() {
        guard !timerRunning else { return }
        if timerRemainingSeconds <= 0 {
            timerRemainingSeconds = timerDurationSeconds
        }
        timerRunning = true
        activeStatusText = "Timer running"
        timerTask?.cancel()
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    break
                }
                await MainActor.run {
                    guard let self, self.timerRunning else { return }
                    self.timerRemainingSeconds = max(0, self.timerRemainingSeconds - 1)
                    if self.timerRemainingSeconds == 0 {
                        self.stopTimer()
                        self.activeStatusText = "Timer complete"
                    }
                }
            }
        }
    }

    func stopTimer() {
        timerTask?.cancel()
        timerTask = nil
        timerRunning = false
    }

    func resetTimer() {
        stopTimer()
        timerRemainingSeconds = timerDurationSeconds
        activeStatusText = "Timer reset"
    }

    private func startStats(refreshRate: SystemMonitorRefreshRate) {
        guard activeStatsRefreshRate != refreshRate || statsTask == nil else { return }
        stopStats()
        activeStatsRefreshRate = refreshRate
        statsTask = Task { [weak self] in
            guard let self else { return }
            await self.sampleStats()
            guard let interval = refreshRate.interval else { return }
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: interval)
                } catch {
                    break
                }
                guard !Task.isCancelled else { break }
                await self.sampleStats()
            }
        }
    }

    private func stopStats() {
        statsTask?.cancel()
        statsTask = nil
        activeStatsRefreshRate = nil
    }

    private func sampleStats() async {
        let snapshot = await sampler.sample()
        await MainActor.run {
            systemSnapshot = snapshot
            activeStatusText = "Stats updated"
        }
    }
}

private extension NSColor {
    var hexString: String {
        guard let color = usingColorSpace(.deviceRGB) else { return "#7C5CFF" }
        let red = Int((color.redComponent * 255).rounded())
        let green = Int((color.greenComponent * 255).rounded())
        let blue = Int((color.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}
