import ApplicationServices
import Foundation

@MainActor
protocol ClaudeDesktopAccessibilityPermissionChecking: AnyObject {
    func isTrusted(prompt: Bool) -> Bool
}

@MainActor
final class SystemClaudeDesktopAccessibilityPermissionChecker: ClaudeDesktopAccessibilityPermissionChecking {
    func isTrusted(prompt: Bool) -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}

enum ClaudeDesktopAccessibilityPermissionDiagnostics {
    static func logNotTrusted(context: String) {
        #if DEBUG
        let buildConfiguration = "Debug"
        #else
        let buildConfiguration = "Release"
        #endif

        let bundleID = Bundle.main.bundleIdentifier ?? "<missing>"
        let bundlePath = Bundle.main.bundlePath
        Log.app.warning(
            "Claude Desktop accessibility permission is still not trusted (\(context, privacy: .public)); bundleID=\(bundleID, privacy: .public), bundlePath=\(bundlePath, privacy: .public), build=\(buildConfiguration, privacy: .public). If System Settings shows permission enabled, the user may have authorized another app copy."
        )
    }
}
