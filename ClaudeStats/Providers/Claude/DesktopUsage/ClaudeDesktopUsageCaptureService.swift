import Foundation

@MainActor
protocol ClaudeDesktopUsageCapturing: AnyObject {
    func capture(trigger: ClaudeDesktopUsageCaptureTrigger) async -> ClaudeDesktopUsageCaptureOutcome
}

@MainActor
final class ClaudeDesktopUsageCaptureService: ClaudeDesktopUsageCapturing {
    private let appLocator: any ClaudeDesktopUsageAppLocating
    private let accessibilityReader: any ClaudeDesktopUsageTextReading
    private let ocrReader: any ClaudeDesktopUsageTextReading
    private let parser: ClaudeDesktopUsageTextParser
    private let cacheWriter: any ClaudeDesktopUsageCacheWriting

    init(
        appLocator: any ClaudeDesktopUsageAppLocating = ClaudeDesktopAppLocator(),
        accessibilityReader: any ClaudeDesktopUsageTextReading = ClaudeDesktopAccessibilityReader(),
        ocrReader: any ClaudeDesktopUsageTextReading = ClaudeDesktopOCRReader(),
        parser: ClaudeDesktopUsageTextParser = ClaudeDesktopUsageTextParser(),
        cacheWriter: any ClaudeDesktopUsageCacheWriting = ClaudeDesktopUsageCacheWriter()
    ) {
        self.appLocator = appLocator
        self.accessibilityReader = accessibilityReader
        self.ocrReader = ocrReader
        self.parser = parser
        self.cacheWriter = cacheWriter
    }

    func capture(trigger: ClaudeDesktopUsageCaptureTrigger) async -> ClaudeDesktopUsageCaptureOutcome {
        var app = appLocator.locate()
        guard app.isInstalled else {
            return .failed(.appNotFound)
        }
        guard app.isRunning else {
            return trigger.shouldShowUserMessage ? .failed(.appNotRunning) : .skipped(.appNotRunning)
        }

        if trigger.allowsActivation {
            _ = appLocator.activateClaudeDesktop()
            try? await Task.sleep(nanoseconds: 300_000_000)
            app = appLocator.locate()
        } else if shouldSkipNonStealingCapture(app: app, trigger: trigger) {
            return .skipped(trigger == .visibleAutomatic ? .notFrontmost : .notVisible)
        }

        let capturedAt = Date()
        switch await snapshotFromAccessibility(app: app, trigger: trigger, capturedAt: capturedAt) {
        case .success(let snapshot):
            return write(snapshot)
        case .failure(let error) where error == .accessibilityPermissionRequired:
            return .failed(error)
        case .failure:
            break
        }

        switch await snapshotFromOCR(app: app, trigger: trigger, capturedAt: capturedAt) {
        case .success(let snapshot):
            return write(snapshot)
        case .failure(let error):
            return .failed(error)
        }
    }

    private func shouldSkipNonStealingCapture(app: ClaudeDesktopAppState, trigger: ClaudeDesktopUsageCaptureTrigger) -> Bool {
        switch trigger {
        case .manual, .permissionRecheck:
            false
        case .visibleAutomatic:
            !app.isFrontmost
        case .timedAutomatic:
            !app.isVisible
        }
    }

    private func snapshotFromAccessibility(
        app: ClaudeDesktopAppState,
        trigger: ClaudeDesktopUsageCaptureTrigger,
        capturedAt: Date
    ) async -> Result<UsageLimitSnapshot, ClaudeDesktopUsageCaptureError> {
        do {
            let text = try await accessibilityReader.readUsageText(app: app, trigger: trigger)
            guard let snapshot = parser.snapshot(from: text, capturedAt: capturedAt) else {
                return .failure(.parseFailed)
            }
            return .success(snapshot)
        } catch let error as ClaudeDesktopUsageCaptureError {
            return .failure(error)
        } catch {
            return .failure(.captureFailed(error.localizedDescription))
        }
    }

    private func snapshotFromOCR(
        app: ClaudeDesktopAppState,
        trigger: ClaudeDesktopUsageCaptureTrigger,
        capturedAt: Date
    ) async -> Result<UsageLimitSnapshot, ClaudeDesktopUsageCaptureError> {
        do {
            let text = try await ocrReader.readUsageText(app: app, trigger: trigger)
            guard let snapshot = parser.snapshot(from: text, capturedAt: capturedAt) else {
                return .failure(.parseFailed)
            }
            return .success(snapshot)
        } catch let error as ClaudeDesktopUsageCaptureError {
            return .failure(error)
        } catch {
            return .failure(.captureFailed(error.localizedDescription))
        }
    }

    private func write(_ snapshot: UsageLimitSnapshot) -> ClaudeDesktopUsageCaptureOutcome {
        do {
            try cacheWriter.write(snapshot)
            return .captured(snapshot)
        } catch {
            return .failed(.cacheWriteFailed(error.localizedDescription))
        }
    }
}
