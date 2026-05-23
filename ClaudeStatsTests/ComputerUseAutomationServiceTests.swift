import Darwin
import CoreGraphics
import Foundation
import Testing
@testable import ClaudeStats

@Suite("Computer Use automation service")
@MainActor
struct ComputerUseAutomationServiceTests {
    @Test("Allowed app can read state and disallowed app is rejected")
    func allowlistControlsAppAccess() throws {
        let backend = FakeComputerUseAutomationBackend()
        let service = ComputerUseAutomationService(
            allowedApps: ["allowed.app"],
            readOnlyBackend: backend,
            controlBackend: backend
        )

        let state = try service.getAppState(app: "allowed.app", policy: .readOnly)

        #expect(state == "state")
        #expect(backend.getAppStateApps == ["allowed.app"])
        #expect(throws: ComputerUseAutomationError.appNotAllowed("blocked.app")) {
            try service.getAppState(app: "blocked.app", policy: .readOnly)
        }
    }

    @Test("Read-only policy rejects actions before touching backend")
    func readOnlyPolicyRejectsActions() {
        let backend = FakeComputerUseAutomationBackend()
        let service = ComputerUseAutomationService(
            allowedApps: ["allowed.app"],
            readOnlyBackend: backend,
            controlBackend: backend
        )

        #expect(throws: ComputerUseAutomationError.actionNotAllowed) {
            try service.click(app: "allowed.app", elementIndex: "12", policy: .readOnly)
        }
        #expect(throws: ComputerUseAutomationError.actionNotAllowed) {
            try service.click(
                app: "allowed.app",
                x: 10,
                y: 10,
                policy: .readOnly,
                allowsForegroundPointerFallback: false
            )
        }

        #expect(backend.clickElementIndices.isEmpty)
        #expect(backend.coordinateClicks.isEmpty)
    }

    @Test("User-initiated policy can perform actions")
    func userInitiatedPolicyPerformsActions() throws {
        let backend = FakeComputerUseAutomationBackend()
        let service = ComputerUseAutomationService(
            allowedApps: ["allowed.app"],
            readOnlyBackend: backend,
            controlBackend: backend
        )

        let state = try service.click(app: "allowed.app", elementIndex: "12", policy: .userInitiatedControl)

        #expect(state == "clicked")
        #expect(backend.clickElementIndices == ["12"])
    }

    @Test("Coordinate foreground fallback is scoped and restores environment")
    func coordinateForegroundFallbackIsScopedAndRestoresEnvironment() throws {
        let key = "OPEN_COMPUTER_USE_ALLOW_GLOBAL_POINTER_FALLBACKS"
        let previousValue = getenv(key).map { String(cString: $0) }
        unsetenv(key)
        defer {
            if let previousValue {
                setenv(key, previousValue, 1)
            } else {
                unsetenv(key)
            }
        }

        let backend = FakeComputerUseAutomationBackend()
        let service = ComputerUseAutomationService(
            readOnlyBackend: backend,
            controlBackend: backend
        )

        let state = try service.click(
            app: ClaudeDesktopAppLocator.bundleIdentifier,
            x: 120,
            y: 240,
            policy: .userInitiatedControl,
            allowsForegroundPointerFallback: true
        )

        #expect(state == "coordinate clicked")
        #expect(backend.coordinateClicks == [CGPoint(x: 120, y: 240)])
        #expect(backend.coordinateClickFallbackValues == ["1"])
        #expect(getenv(key) == nil)
    }
}

@MainActor
private final class FakeComputerUseAutomationBackend: ComputerUseAutomationBackend {
    private(set) var getAppStateApps: [String] = []
    private(set) var clickElementIndices: [String] = []
    private(set) var coordinateClicks: [CGPoint] = []
    private(set) var coordinateClickFallbackValues: [String?] = []

    func getAppSnapshot(app: String) throws -> ComputerUseAutomationSnapshot {
        ComputerUseAutomationSnapshot(
            text: "state",
            windowSize: CGSize(width: 400, height: 300),
            screenshotPixelSize: CGSize(width: 800, height: 600),
            elements: []
        )
    }

    func getAppState(app: String) throws -> String {
        getAppStateApps.append(app)
        return "state"
    }

    func click(app: String, elementIndex: String) throws -> String {
        clickElementIndices.append(elementIndex)
        return "clicked"
    }

    func click(app: String, x: Double, y: Double) throws -> String {
        coordinateClicks.append(CGPoint(x: x, y: y))
        coordinateClickFallbackValues.append(getenv("OPEN_COMPUTER_USE_ALLOW_GLOBAL_POINTER_FALLBACKS").map { String(cString: $0) })
        return "coordinate clicked"
    }

    func pressKey(app: String, key: String) throws -> String {
        "pressed"
    }

    func typeText(app: String, text: String) throws -> String {
        "typed"
    }

    func setValue(app: String, elementIndex: String, value: String) throws -> String {
        "set"
    }
}
