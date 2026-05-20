import Foundation
import Testing
@testable import ClaudeStats

@Suite("Claude Desktop accessibility reader")
@MainActor
struct ClaudeDesktopAccessibilityReaderTests {
    @Test("Manual capture asks macOS to prompt for accessibility permission")
    func manualCapturePromptsForAccessibilityPermission() async {
        let permission = FakeClaudeDesktopAccessibilityPermissionChecker(isTrusted: false)
        let reader = ClaudeDesktopAccessibilityReader(permissionChecker: permission)

        await #expect(throws: ClaudeDesktopUsageCaptureError.accessibilityPermissionRequired) {
            try await reader.readUsageText(app: Self.runningApp, trigger: .manual)
        }

        #expect(permission.promptValues == [true])
    }

    @Test("Automatic capture checks accessibility permission without prompting")
    func automaticCaptureDoesNotPromptForAccessibilityPermission() async {
        let permission = FakeClaudeDesktopAccessibilityPermissionChecker(isTrusted: false)
        let reader = ClaudeDesktopAccessibilityReader(permissionChecker: permission)

        await #expect(throws: ClaudeDesktopUsageCaptureError.accessibilityPermissionRequired) {
            try await reader.readUsageText(app: Self.runningApp, trigger: .visibleAutomatic)
        }

        #expect(permission.promptValues == [false])
    }

    @Test("Permission recheck checks accessibility permission without prompting")
    func permissionRecheckDoesNotPromptForAccessibilityPermission() async {
        let permission = FakeClaudeDesktopAccessibilityPermissionChecker(isTrusted: false)
        let reader = ClaudeDesktopAccessibilityReader(permissionChecker: permission)

        await #expect(throws: ClaudeDesktopUsageCaptureError.accessibilityPermissionRequired) {
            try await reader.readUsageText(app: Self.runningApp, trigger: .permissionRecheck)
        }

        #expect(permission.promptValues == [false])
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
private final class FakeClaudeDesktopAccessibilityPermissionChecker: ClaudeDesktopAccessibilityPermissionChecking {
    let trusted: Bool
    private(set) var promptValues: [Bool] = []

    init(isTrusted: Bool) {
        self.trusted = isTrusted
    }

    func isTrusted(prompt: Bool) -> Bool {
        promptValues.append(prompt)
        return trusted
    }
}
