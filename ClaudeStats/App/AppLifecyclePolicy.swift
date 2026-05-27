import Foundation

/// Keeps Codex Statistics resident while it is running as a menu-bar utility.
@MainActor
enum AppLifecyclePolicy {
    static let automaticTerminationReason = "Codex Statistics is a resident menu-bar app."
    private static var processInfo: AutomaticTerminationControlling = ProcessInfo.processInfo

    static func configureAutomaticTermination(using processInfo: AutomaticTerminationControlling = ProcessInfo.processInfo) {
        self.processInfo = processInfo
        reassertAutomaticTerminationPolicy()
    }

    static func reassertAutomaticTerminationPolicy() {
        processInfo.disableAutomaticTermination(automaticTerminationReason)
    }

    /// AppKit briefly re-enables automatic termination while finishing its
    /// launch/window-restoration bookkeeping. Reassert after that first pass so
    /// the menu-bar host remains resident when no standard window is open.
    static func reassertAfterLaunchRestoration() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            Task { @MainActor in
                reassertAutomaticTerminationPolicy()
            }
        }
    }
}

protocol AutomaticTerminationControlling {
    func disableAutomaticTermination(_ reason: String)
}

extension ProcessInfo: AutomaticTerminationControlling {}
