import Foundation

@MainActor
protocol ClaudeDesktopUsageCapturing: AnyObject {
    func capture(trigger: ClaudeDesktopUsageCaptureTrigger) async -> ClaudeDesktopUsageCaptureOutcome
}

@MainActor
final class ClaudeDesktopUsageCaptureService: ClaudeDesktopUsageCapturing {
    private let appLocator: any ClaudeDesktopUsageAppLocating
    private let computerUseReader: any ClaudeDesktopUsageTextReading
    private let accessibilityReader: any ClaudeDesktopUsageTextReading
    private let ocrReader: any ClaudeDesktopUsageTextReading
    private let parser: ClaudeDesktopUsageTextParser
    private let cacheWriter: any ClaudeDesktopUsageCacheWriting

    init(
        appLocator: any ClaudeDesktopUsageAppLocating = ClaudeDesktopAppLocator(),
        computerUseReader: any ClaudeDesktopUsageTextReading = ClaudeDesktopComputerUseReader(),
        accessibilityReader: any ClaudeDesktopUsageTextReading = ClaudeDesktopAccessibilityReader(),
        ocrReader: any ClaudeDesktopUsageTextReading = ClaudeDesktopOCRReader(),
        parser: ClaudeDesktopUsageTextParser = ClaudeDesktopUsageTextParser(),
        cacheWriter: any ClaudeDesktopUsageCacheWriting = ClaudeDesktopUsageCacheWriter()
    ) {
        self.appLocator = appLocator
        self.computerUseReader = computerUseReader
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
        var failures: [ClaudeDesktopUsageCaptureError] = []
        var bestSnapshot: UsageLimitSnapshot?
        let readers: [(label: String, reader: any ClaudeDesktopUsageTextReading)] = [
            ("ComputerUse", computerUseReader),
            ("AX", accessibilityReader),
            ("OCR", ocrReader),
        ]
        for item in readers {
            switch await snapshot(from: item.reader, app: app, trigger: trigger, capturedAt: capturedAt) {
            case .success(let snapshot):
                let merged = snapshotByMerging(bestSnapshot, with: snapshot)
                bestSnapshot = betterSnapshot(merged, than: bestSnapshot)
                logManual(trigger, "\(item.label) usage snapshot ids=\(windowIDs(snapshot.windows)), best=\(windowIDs(bestSnapshot?.windows ?? [])), coreComplete=\(UsageLimitWindowCatalog.isClaudeCoreComplete(bestSnapshot?.windows ?? [])).")
                if UsageLimitWindowCatalog.isClaudeCoreComplete(bestSnapshot?.windows ?? []) {
                    return write(bestSnapshot ?? snapshot)
                }
            case .failure(let error):
                failures.append(error)
            }
        }

        if let bestSnapshot {
            logManual(trigger, "Writing best partial Claude usage snapshot ids=\(windowIDs(bestSnapshot.windows)).")
            return write(bestSnapshot)
        }

        return .failed(preferredFailure(from: failures))
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

    private func snapshot(
        from reader: any ClaudeDesktopUsageTextReading,
        app: ClaudeDesktopAppState,
        trigger: ClaudeDesktopUsageCaptureTrigger,
        capturedAt: Date
    ) async -> Result<UsageLimitSnapshot, ClaudeDesktopUsageCaptureError> {
        do {
            let text = try await reader.readUsageText(app: app, trigger: trigger)
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

    private func snapshotByMerging(_ existing: UsageLimitSnapshot?, with incoming: UsageLimitSnapshot) -> UsageLimitSnapshot {
        guard let existing else { return incoming }
        var windowsByID = Dictionary(uniqueKeysWithValues: existing.windows.map { ($0.id, $0) })
        for window in incoming.windows {
            windowsByID[window.id] = window
        }
        return UsageLimitSnapshot(
            provider: incoming.provider,
            windows: UsageLimitWindowCatalog.orderedClaudeWindows(Array(windowsByID.values)),
            capturedAt: incoming.capturedAt,
            sourceLabel: incoming.sourceLabel,
            sourcePath: incoming.sourcePath,
            planType: incoming.planType,
            limitID: incoming.limitID
        )
    }

    private func betterSnapshot(_ snapshot: UsageLimitSnapshot, than current: UsageLimitSnapshot?) -> UsageLimitSnapshot {
        guard let current else { return snapshot }
        let snapshotCoreComplete = UsageLimitWindowCatalog.isClaudeCoreComplete(snapshot.windows)
        let currentCoreComplete = UsageLimitWindowCatalog.isClaudeCoreComplete(current.windows)
        if snapshotCoreComplete != currentCoreComplete {
            return snapshotCoreComplete ? snapshot : current
        }
        if snapshot.windows.count != current.windows.count {
            return snapshot.windows.count > current.windows.count ? snapshot : current
        }
        return snapshot
    }

    private func preferredFailure(from failures: [ClaudeDesktopUsageCaptureError]) -> ClaudeDesktopUsageCaptureError {
        for permissionFailure in [ClaudeDesktopUsageCaptureError.accessibilityPermissionRequired, .screenRecordingPermissionRequired] {
            if failures.contains(permissionFailure) {
                return permissionFailure
            }
        }

        if failures.contains(.parseFailed) {
            return .parseFailed
        }

        return failures.last ?? .noUsageText
    }

    private func write(_ snapshot: UsageLimitSnapshot) -> ClaudeDesktopUsageCaptureOutcome {
        do {
            try cacheWriter.write(snapshot)
            return .captured(snapshot)
        } catch {
            return .failed(.cacheWriteFailed(error.localizedDescription))
        }
    }

    private func logManual(_ trigger: ClaudeDesktopUsageCaptureTrigger, _ message: String) {
        guard trigger == .manual else { return }
        Log.app.debug("\(message, privacy: .public)")
    }

    private func windowIDs(_ windows: [UsageLimitWindow]) -> String {
        windows.map(\.id).joined(separator: ",")
    }
}
