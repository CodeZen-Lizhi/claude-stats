import AppKit
import OSLog
import UserNotifications

/// Host shim used by the embedded Ghostty sources.
///
/// Several upstream macOS Ghostty files look up `NSApp.delegate as? AppDelegate`.
/// Claude Stats' app delegate subclasses this type, so those lookups continue to
/// work while the terminal runtime stays owned by the embedding app.
open class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate, Ghostty.Delegate {
    static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.claudestats.ClaudeStats",
        category: String(describing: AppDelegate.self)
    )

    let terminalStore: EmbeddedTerminalStore
    var ghostty: Ghostty.App {
        MainActor.assumeIsolated {
            terminalStore.ghostty
        }
    }
    lazy var undoManager = ExpiringUndoManager()
    let updateController = UpdateController()
    var updateViewModel: UpdateViewModel { updateController.viewModel }
    var hiddenState: ToggleVisibilityState?

    public override init() {
        self.terminalStore = MainActor.assumeIsolated {
            EmbeddedTerminalStore()
        }
        super.init()
    }

    public init(terminalStore: EmbeddedTerminalStore) {
        self.terminalStore = terminalStore
        super.init()
    }

    open func applicationDidFinishLaunching(_ notification: Notification) {}

    @objc func checkForUpdates(_ sender: Any?) {
        updateController.checkForUpdates()
    }

    @objc func closeAllWindows(_ sender: Any?) {
        MainActor.assumeIsolated {
            terminalStore.closeAllTabs(force: false)
        }
    }

    @objc func toggleVisibility(_ sender: Any?) {}

    @objc func toggleQuickTerminal(_ sender: Any?) {}

    func syncFloatOnTopMenu(_ window: NSWindow) {}

    func performGhosttyBindingMenuKeyEquivalent(with event: NSEvent) -> Bool {
        false
    }

    func setSecureInput(_ mode: Ghostty.SetSecureInput) {
        switch mode {
        case .on:
            SecureInput.shared.global = true
        case .off:
            SecureInput.shared.global = false
        case .toggle:
            SecureInput.shared.global.toggle()
        }
    }

    func ghosttySurface(id: UUID) -> Ghostty.SurfaceView? {
        MainActor.assumeIsolated {
            terminalStore.ghosttySurface(id: id)
        }
    }

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        ghostty.handleUserNotification(response: response)
        completionHandler()
    }

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let options: UNNotificationPresentationOptions = ghostty.shouldPresentNotification(notification: notification)
            ? [.banner, .sound]
            : []
        completionHandler(options)
    }

    struct ToggleVisibilityState {
        func restore() {}
    }
}
