import CoreGraphics
import Foundation
import Testing
@testable import ClaudeStats

@Suite("Claude Desktop Computer Use reader")
@MainActor
struct ClaudeDesktopComputerUseReaderTests {
    @Test("Parseable snapshot text is returned without actions")
    func parseableSnapshotTextReturnsWithoutActions() async throws {
        let automation = FakeComputerUseAutomation(
            snapshots: [.text("App=com.anthropic.claudefordesktop\n5h\n94% left\n6% used")]
        )
        let reader = ClaudeDesktopComputerUseReader(automation: automation)

        let text = try await reader.readUsageText(app: Self.runningApp, trigger: .manual)

        #expect(text.contains("6% used"))
        #expect(automation.getAppSnapshotPolicies == [.userInitiatedControl])
        #expect(automation.clickElementIndices.isEmpty)
    }

    @Test("Manual partial snapshot continues to click usage candidate for core limits")
    func manualPartialSnapshotContinuesToClickUsageCandidate() async throws {
        let automation = FakeComputerUseAutomation(
            snapshots: [
                .text(
                    "App=com.anthropic.claudefordesktop\n7d\n0%\n12 button Usage limits",
                    elements: [
                        .element(index: "12", role: "AXButton", label: "12 button Usage limits"),
                    ]
                ),
            ],
            clickText: "Plan usage\n5-hour limit\n6%\nWeekly · all models\n3%"
        )
        let reader = ClaudeDesktopComputerUseReader(automation: automation)

        let text = try await reader.readUsageText(app: Self.runningApp, trigger: .manual)

        #expect(text.contains("5-hour limit"))
        #expect(automation.clickElementIndices == ["12"])
    }

    @Test("Manual capture clicks a usage candidate and rereads")
    func manualCaptureClicksUsageCandidate() async throws {
        let automation = FakeComputerUseAutomation(
            snapshots: [
                .text(
                    "App=com.anthropic.claudefordesktop\n12 button Usage limits",
                    elements: [
                        .element(index: "12", role: "AXButton", label: "12 button Usage limits"),
                    ]
                ),
            ],
            clickText: "App=com.anthropic.claudefordesktop\n5h\n6% used\n7d\n3% used"
        )
        let reader = ClaudeDesktopComputerUseReader(automation: automation)

        let text = try await reader.readUsageText(app: Self.runningApp, trigger: .manual)

        #expect(text.contains("6% used"))
        #expect(automation.clickElementIndices == ["12"])
        #expect(automation.clickPolicies == [.userInitiatedControl])
    }

    @Test("Manual capture clicks bottom trailing no-label usage candidate")
    func manualCaptureClicksBottomTrailingNoLabelCandidate() async throws {
        let automation = FakeComputerUseAutomation(
            snapshots: [
                .text(
                    "App=com.anthropic.claudefordesktop\n42 button",
                    windowSize: CGSize(width: 1_000, height: 800),
                    elements: [
                        .element(
                            index: "42",
                            role: "AXButton",
                            label: "42 button",
                            frame: CGRect(x: 895, y: 725, width: 34, height: 34)
                        ),
                    ]
                ),
            ],
            clickText: "Plan usage\n5-hour limit\n6%\nWeekly · all models\n3%"
        )
        let reader = ClaudeDesktopComputerUseReader(automation: automation)

        let text = try await reader.readUsageText(app: Self.runningApp, trigger: .manual)

        #expect(text.contains("5-hour limit"))
        #expect(automation.clickElementIndices == ["42"])
        #expect(automation.coordinateClicks.isEmpty)
    }

    @Test("Manual capture uses bottom-right coordinate fallback")
    func manualCaptureUsesCoordinateFallback() async throws {
        let automation = FakeComputerUseAutomation(
            snapshots: [
                .text(
                    "App=com.anthropic.claudefordesktop\n0 window Claude",
                    windowSize: CGSize(width: 1_000, height: 800),
                    screenshotPixelSize: CGSize(width: 2_000, height: 1_600)
                ),
            ],
            coordinateClickText: "Plan usage\n5-hour limit\n6%\nWeekly · all models\n3%"
        )
        let reader = ClaudeDesktopComputerUseReader(automation: automation)

        let text = try await reader.readUsageText(app: Self.runningApp, trigger: .manual)

        #expect(text.contains("5-hour limit"))
        #expect(automation.clickElementIndices.isEmpty)
        #expect(automation.coordinateClicks == [CGPoint(x: 1_824, y: 1_484)])
        #expect(automation.coordinateClickForegroundFallbacks == [true])
    }

    @Test("Automatic parseable partial snapshot stays read-only")
    func automaticParseablePartialSnapshotStaysReadOnly() async throws {
        let automation = FakeComputerUseAutomation(
            snapshots: [
                .text(
                    "App=com.anthropic.claudefordesktop\n12 button Usage limits\n7d\n0%",
                    elements: [
                        .element(index: "12", role: "AXButton", label: "12 button Usage limits"),
                    ]
                ),
            ]
        )
        let reader = ClaudeDesktopComputerUseReader(automation: automation)

        let text = try await reader.readUsageText(app: Self.runningApp, trigger: .visibleAutomatic)

        #expect(text.contains("7d"))
        #expect(automation.getAppSnapshotPolicies == [.readOnly])
        #expect(automation.clickElementIndices.isEmpty)
    }

    @Test("Automatic capture stays read-only")
    func automaticCaptureStaysReadOnly() async {
        let automation = FakeComputerUseAutomation(
            snapshots: [
                .text(
                    "App=com.anthropic.claudefordesktop\n12 button Usage limits",
                    elements: [
                        .element(index: "12", role: "AXButton", label: "12 button Usage limits"),
                    ]
                ),
            ]
        )
        let reader = ClaudeDesktopComputerUseReader(automation: automation)

        await #expect(throws: ClaudeDesktopUsageCaptureError.noUsageText) {
            try await reader.readUsageText(app: Self.runningApp, trigger: .visibleAutomatic)
        }

        #expect(automation.getAppSnapshotPolicies == [.readOnly])
        #expect(automation.clickElementIndices.isEmpty)
        #expect(automation.coordinateClicks.isEmpty)
    }

    @Test("Accessibility tool errors map to permission errors")
    func accessibilityToolErrorsMapToPermissionErrors() async {
        let automation = FakeComputerUseAutomation(error: ComputerUseAutomationError.toolFailed("Accessibility permission is required."))
        let reader = ClaudeDesktopComputerUseReader(automation: automation)

        await #expect(throws: ClaudeDesktopUsageCaptureError.accessibilityPermissionRequired) {
            try await reader.readUsageText(app: Self.runningApp, trigger: .manual)
        }
    }

    private static let runningApp = ClaudeDesktopAppState(
        isInstalled: true,
        isRunning: true,
        isVisible: true,
        isFrontmost: true,
        processIdentifier: 123,
        localizedName: "Claude"
    )
}

@MainActor
private final class FakeComputerUseAutomation: ComputerUseAutomating {
    private var snapshots: [ComputerUseAutomationSnapshot]
    private let clickText: String?
    private let coordinateClickText: String?
    private let error: Error?
    private(set) var getAppSnapshotPolicies: [ComputerUseAutomationPolicy] = []
    private(set) var clickPolicies: [ComputerUseAutomationPolicy] = []
    private(set) var clickElementIndices: [String] = []
    private(set) var coordinateClicks: [CGPoint] = []
    private(set) var coordinateClickForegroundFallbacks: [Bool] = []

    init(
        snapshots: [ComputerUseAutomationSnapshot] = [],
        clickText: String? = nil,
        coordinateClickText: String? = nil,
        error: Error? = nil
    ) {
        self.snapshots = snapshots
        self.clickText = clickText
        self.coordinateClickText = coordinateClickText
        self.error = error
    }

    init(error: Error) {
        self.snapshots = []
        self.clickText = nil
        self.coordinateClickText = nil
        self.error = error
    }

    func getAppSnapshot(app: String, policy: ComputerUseAutomationPolicy) throws -> ComputerUseAutomationSnapshot {
        getAppSnapshotPolicies.append(policy)
        if let error { throw error }
        guard !snapshots.isEmpty else { return .text("") }
        return snapshots.removeFirst()
    }

    func getAppState(app: String, policy: ComputerUseAutomationPolicy) throws -> String {
        try getAppSnapshot(app: app, policy: policy).text
    }

    func click(app: String, elementIndex: String, policy: ComputerUseAutomationPolicy) throws -> String {
        clickElementIndices.append(elementIndex)
        clickPolicies.append(policy)
        if let error { throw error }
        return clickText ?? ""
    }

    func click(
        app: String,
        x: Double,
        y: Double,
        policy: ComputerUseAutomationPolicy,
        allowsForegroundPointerFallback: Bool
    ) throws -> String {
        coordinateClicks.append(CGPoint(x: x, y: y))
        coordinateClickForegroundFallbacks.append(allowsForegroundPointerFallback)
        if let error { throw error }
        return coordinateClickText ?? ""
    }

    func pressKey(app: String, key: String, policy: ComputerUseAutomationPolicy) throws -> String {
        ""
    }

    func typeText(app: String, text: String, policy: ComputerUseAutomationPolicy) throws -> String {
        ""
    }

    func setValue(app: String, elementIndex: String, value: String, policy: ComputerUseAutomationPolicy) throws -> String {
        ""
    }
}

private extension ComputerUseAutomationSnapshot {
    static func text(
        _ text: String,
        windowSize: CGSize? = nil,
        screenshotPixelSize: CGSize? = nil,
        elements: [ComputerUseAutomationElement] = []
    ) -> ComputerUseAutomationSnapshot {
        ComputerUseAutomationSnapshot(
            text: text,
            windowSize: windowSize,
            screenshotPixelSize: screenshotPixelSize,
            elements: elements
        )
    }
}

private extension ComputerUseAutomationElement {
    static func element(
        index: String,
        role: String,
        label: String,
        frame: CGRect? = nil
    ) -> ComputerUseAutomationElement {
        ComputerUseAutomationElement(
            index: index,
            role: role,
            label: label,
            actions: [],
            frame: frame,
            isSyntheticText: false
        )
    }
}
