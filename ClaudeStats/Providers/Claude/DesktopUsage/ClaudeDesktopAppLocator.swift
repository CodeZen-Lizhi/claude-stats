import AppKit

@MainActor
protocol ClaudeDesktopUsageAppLocating: AnyObject {
    func locate() -> ClaudeDesktopAppState
    func activateClaudeDesktop() -> Bool
}

@MainActor
final class ClaudeDesktopAppLocator: ClaudeDesktopUsageAppLocating {
    static let bundleIdentifier = "com.anthropic.claudefordesktop"

    private let workspace: NSWorkspace

    init(workspace: NSWorkspace = .shared) {
        self.workspace = workspace
    }

    func locate() -> ClaudeDesktopAppState {
        let appURL = workspace.urlForApplication(withBundleIdentifier: Self.bundleIdentifier)
        guard let app = runningApp else {
            return ClaudeDesktopAppState(
                isInstalled: appURL != nil,
                isRunning: false,
                isVisible: false,
                isFrontmost: false,
                processIdentifier: nil,
                localizedName: nil
            )
        }

        return ClaudeDesktopAppState(
            isInstalled: appURL != nil,
            isRunning: true,
            isVisible: app.activationPolicy != .prohibited && !app.isHidden,
            isFrontmost: app.isActive,
            processIdentifier: app.processIdentifier,
            localizedName: app.localizedName
        )
    }

    func activateClaudeDesktop() -> Bool {
        runningApp?.activate(options: [.activateAllWindows, .activateIgnoringOtherApps]) ?? false
    }

    private var runningApp: NSRunningApplication? {
        workspace.runningApplications.first { app in
            app.bundleIdentifier == Self.bundleIdentifier
        }
    }
}
