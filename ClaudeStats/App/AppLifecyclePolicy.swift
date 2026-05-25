import Foundation

/// Keeps Claude Stats resident while it is running as a menu-bar utility.
enum AppLifecyclePolicy {
    static let automaticTerminationReason = "Claude Stats is a resident menu-bar app."

    @MainActor
    static func configureAutomaticTermination(using processInfo: AutomaticTerminationControlling = ProcessInfo.processInfo) {
        processInfo.disableAutomaticTermination(automaticTerminationReason)
    }

    /// AppKit briefly re-enables automatic termination while finishing its
    /// launch/window-restoration bookkeeping. Reassert after that first pass so
    /// the menu-bar host remains resident when no standard window is open.
    @MainActor
    static func reassertAfterLaunchRestoration() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            Task { @MainActor in
                configureAutomaticTermination()
            }
        }
    }
}

protocol AutomaticTerminationControlling {
    func disableAutomaticTermination(_ reason: String)
}

extension ProcessInfo: AutomaticTerminationControlling {}
