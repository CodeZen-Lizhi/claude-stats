import AppKit
import Foundation

@MainActor
protocol ClaudeDesktopScreenRecordingPermissionChecking: AnyObject {
    func hasAccess(prompt: Bool) -> Bool
}

@MainActor
final class SystemClaudeDesktopScreenRecordingPermissionChecker: ClaudeDesktopScreenRecordingPermissionChecking {
    func hasAccess(prompt: Bool) -> Bool {
        if CGPreflightScreenCaptureAccess() {
            return true
        }
        guard prompt else {
            return false
        }
        return CGRequestScreenCaptureAccess()
    }
}
