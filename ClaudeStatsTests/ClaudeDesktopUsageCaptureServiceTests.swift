import Foundation
import Testing
@testable import ClaudeStats

@Suite("Claude Desktop usage capture service")
@MainActor
struct ClaudeDesktopUsageCaptureServiceTests {
    @Test("Complete Computer Use success writes snapshot before other readers")
    func completeComputerUseSuccessWritesSnapshotBeforeOtherReaders() async throws {
        let locator = FakeClaudeDesktopLocator()
        locator.state = Self.runningState(isVisible: true, isFrontmost: true)
        let computerUse = FakeClaudeDesktopTextReader(text: "App=com.anthropic.claudefordesktop\n5h\n6% used\n7d\n3% used")
        let accessibility = FakeClaudeDesktopTextReader(text: "unused")
        let writer = FakeClaudeDesktopUsageCacheWriter()
        let service = ClaudeDesktopUsageCaptureService(
            appLocator: locator,
            computerUseReader: computerUse,
            accessibilityReader: accessibility,
            ocrReader: FakeClaudeDesktopTextReader(text: "unused"),
            cacheWriter: writer
        )

        let outcome = await service.capture(trigger: .manual)

        guard case .captured(let snapshot) = outcome else {
            Issue.record("Expected captured outcome, got \(String(describing: outcome))")
            return
        }
        #expect(computerUse.callCount == 1)
        #expect(accessibility.callCount == 0)
        #expect(snapshot.windows.map(\.usedPercent) == [6, 3])
        #expect(writer.snapshots.count == 1)
    }

    @Test("Partial Computer Use result continues and writes complete merged snapshot")
    func partialComputerUseContinuesAndWritesCompleteMergedSnapshot() async throws {
        let locator = FakeClaudeDesktopLocator()
        locator.state = Self.runningState(isVisible: true, isFrontmost: true)
        let computerUse = FakeClaudeDesktopTextReader(text: "7d\n3% used")
        let accessibility = FakeClaudeDesktopTextReader(text: "5h\n6% used")
        let writer = FakeClaudeDesktopUsageCacheWriter()
        let service = ClaudeDesktopUsageCaptureService(
            appLocator: locator,
            computerUseReader: computerUse,
            accessibilityReader: accessibility,
            ocrReader: FakeClaudeDesktopTextReader(text: "unused"),
            cacheWriter: writer
        )

        let outcome = await service.capture(trigger: .manual)

        guard case .captured(let snapshot) = outcome else {
            Issue.record("Expected captured outcome, got \(String(describing: outcome))")
            return
        }
        #expect(computerUse.callCount == 1)
        #expect(accessibility.callCount == 1)
        #expect(snapshot.windows.map(\.id) == ["five_hour", "seven_day"])
        #expect(snapshot.windows.map(\.usedPercent) == [6, 3])
        #expect(writer.snapshots.count == 1)
    }

    @Test("Accessibility success writes snapshot")
    func accessibilitySuccessWritesSnapshot() async throws {
        let locator = FakeClaudeDesktopLocator()
        locator.state = Self.runningState(isVisible: true, isFrontmost: false)
        let computerUse = FakeClaudeDesktopTextReader(error: ClaudeDesktopUsageCaptureError.noUsageText)
        let accessibility = FakeClaudeDesktopTextReader(text: "5h\n94% left\n6% used\n7d\n3% used")
        let ocr = FakeClaudeDesktopTextReader(text: "unused")
        let writer = FakeClaudeDesktopUsageCacheWriter()
        let service = ClaudeDesktopUsageCaptureService(
            appLocator: locator,
            computerUseReader: computerUse,
            accessibilityReader: accessibility,
            ocrReader: ocr,
            cacheWriter: writer
        )

        let outcome = await service.capture(trigger: .manual)

        guard case .captured(let snapshot) = outcome else {
            Issue.record("Expected captured outcome, got \(String(describing: outcome))")
            return
        }
        #expect(locator.activateCallCount == 1)
        #expect(computerUse.callCount == 1)
        #expect(accessibility.callCount == 1)
        #expect(ocr.callCount == 0)
        #expect(snapshot.windows.first?.usedPercent == 6)
        #expect(writer.snapshots.count == 1)
    }

    @Test("Accessibility permission still allows OCR fallback")
    func accessibilityPermissionStillAllowsOCRFallback() async {
        let locator = FakeClaudeDesktopLocator()
        locator.state = Self.runningState(isVisible: true, isFrontmost: true)
        let computerUse = FakeClaudeDesktopTextReader(error: ClaudeDesktopUsageCaptureError.noUsageText)
        let accessibility = FakeClaudeDesktopTextReader(error: ClaudeDesktopUsageCaptureError.accessibilityPermissionRequired)
        let ocr = FakeClaudeDesktopTextReader(text: "5h\n6% used")
        let writer = FakeClaudeDesktopUsageCacheWriter()
        let service = ClaudeDesktopUsageCaptureService(
            appLocator: locator,
            computerUseReader: computerUse,
            accessibilityReader: accessibility,
            ocrReader: ocr,
            cacheWriter: writer
        )

        let outcome = await service.capture(trigger: .manual)

        guard case .captured(let snapshot) = outcome else {
            Issue.record("Expected captured outcome, got \(String(describing: outcome))")
            return
        }
        #expect(ocr.callCount == 1)
        #expect(snapshot.windows.first?.usedPercent == 6)
        #expect(writer.snapshots.count == 1)
    }

    @Test("OCR fallback writes snapshot")
    func ocrFallbackWritesSnapshot() async throws {
        let locator = FakeClaudeDesktopLocator()
        locator.state = Self.runningState(isVisible: true, isFrontmost: true)
        let computerUse = FakeClaudeDesktopTextReader(error: ClaudeDesktopUsageCaptureError.noUsageText)
        let accessibility = FakeClaudeDesktopTextReader(error: ClaudeDesktopUsageCaptureError.noUsageText)
        let ocr = FakeClaudeDesktopTextReader(text: "5h\n94% left\n7d\n3% used")
        let writer = FakeClaudeDesktopUsageCacheWriter()
        let service = ClaudeDesktopUsageCaptureService(
            appLocator: locator,
            computerUseReader: computerUse,
            accessibilityReader: accessibility,
            ocrReader: ocr,
            cacheWriter: writer
        )

        let outcome = await service.capture(trigger: .manual)

        guard case .captured(let snapshot) = outcome else {
            Issue.record("Expected captured outcome, got \(String(describing: outcome))")
            return
        }
        #expect(computerUse.callCount == 1)
        #expect(accessibility.callCount == 1)
        #expect(ocr.callCount == 1)
        #expect(snapshot.windows.map(\.usedPercent) == [6, 3])
        #expect(writer.snapshots.count == 1)
    }

    @Test("Automatic capture skips when not visible and does not write")
    func automaticSkipsWhenNotVisible() async {
        let locator = FakeClaudeDesktopLocator()
        locator.state = Self.runningState(isVisible: false, isFrontmost: false)
        let accessibility = FakeClaudeDesktopTextReader(text: "5h\n6% used")
        let writer = FakeClaudeDesktopUsageCacheWriter()
        let service = ClaudeDesktopUsageCaptureService(
            appLocator: locator,
            computerUseReader: FakeClaudeDesktopTextReader(text: "5h\n6% used"),
            accessibilityReader: accessibility,
            ocrReader: FakeClaudeDesktopTextReader(text: "5h\n6% used"),
            cacheWriter: writer
        )

        let outcome = await service.capture(trigger: .timedAutomatic)

        #expect(outcome == .skipped(.notVisible))
        #expect(locator.activateCallCount == 0)
        #expect(accessibility.callCount == 0)
        #expect(writer.snapshots.isEmpty)
    }

    @Test("Unparseable text does not write cache")
    func unparseableTextDoesNotWriteCache() async {
        let locator = FakeClaudeDesktopLocator()
        locator.state = Self.runningState(isVisible: true, isFrontmost: true)
        let writer = FakeClaudeDesktopUsageCacheWriter()
        let service = ClaudeDesktopUsageCaptureService(
            appLocator: locator,
            computerUseReader: FakeClaudeDesktopTextReader(text: "Projects\nSettings"),
            accessibilityReader: FakeClaudeDesktopTextReader(text: "Projects\nSettings"),
            ocrReader: FakeClaudeDesktopTextReader(text: "Still no quota text"),
            cacheWriter: writer
        )

        let outcome = await service.capture(trigger: .manual)

        #expect(outcome == .failed(.parseFailed))
        #expect(writer.snapshots.isEmpty)
    }

    private static func runningState(isVisible: Bool, isFrontmost: Bool) -> ClaudeDesktopAppState {
        ClaudeDesktopAppState(
            isInstalled: true,
            isRunning: true,
            isVisible: isVisible,
            isFrontmost: isFrontmost,
            processIdentifier: 123,
            localizedName: "Claude"
        )
    }
}

@MainActor
private final class FakeClaudeDesktopLocator: ClaudeDesktopUsageAppLocating {
    var state: ClaudeDesktopAppState = .missing
    private(set) var activateCallCount = 0

    func locate() -> ClaudeDesktopAppState {
        state
    }

    func activateClaudeDesktop() -> Bool {
        activateCallCount += 1
        state = ClaudeDesktopAppState(
            isInstalled: state.isInstalled,
            isRunning: state.isRunning,
            isVisible: true,
            isFrontmost: true,
            processIdentifier: state.processIdentifier,
            localizedName: state.localizedName
        )
        return true
    }
}

@MainActor
private final class FakeClaudeDesktopTextReader: ClaudeDesktopUsageTextReading {
    let text: String?
    let error: Error?
    private(set) var callCount = 0

    init(text: String) {
        self.text = text
        self.error = nil
    }

    init(error: Error) {
        self.text = nil
        self.error = error
    }

    func readUsageText(app: ClaudeDesktopAppState, trigger: ClaudeDesktopUsageCaptureTrigger) async throws -> String {
        callCount += 1
        if let error { throw error }
        return text ?? ""
    }
}

private final class FakeClaudeDesktopUsageCacheWriter: ClaudeDesktopUsageCacheWriting, @unchecked Sendable {
    private(set) var snapshots: [UsageLimitSnapshot] = []

    func write(_ snapshot: UsageLimitSnapshot) throws {
        snapshots.append(snapshot)
    }
}
