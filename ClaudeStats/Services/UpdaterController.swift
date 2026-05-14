import AppKit
import Sparkle

/// Owns Sparkle's standard updater for the lifetime of the app (created in
/// ``AppEnvironment``, started once AppKit has finished launching via
/// ``AppEnvironment/start()``).
///
/// Claude Stats runs as a menu-bar (`LSUIElement`) app, so it has no Dock icon
/// and its windows don't normally come to the front. While Sparkle's update
/// windows are on screen we route through ``DockVisibilityCoordinator`` to
/// promote the app to a regular, Dock-visible app, then release back to
/// `.accessory` when the update session ends — otherwise the "update available"
/// dialog can appear behind everything with no way to focus it. The coordinator
/// is ref-counted so this composes with other consumers (e.g. the main window).
final class UpdaterController: NSObject {
    private var controller: SPUStandardUpdaterController?

    /// Create and start the Sparkle updater. Idempotent; safe to call once at
    /// launch. Kept out of `init` so `AppEnvironment.preview()` / tests can hold
    /// an `UpdaterController` without spinning up Sparkle.
    @MainActor
    func start() {
        guard controller == nil else { return }
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: self
        )
    }

    @MainActor
    var canCheckForUpdates: Bool {
        controller?.updater.canCheckForUpdates ?? false
    }

    /// Trigger a user-initiated update check (e.g. from Settings ▸ About).
    /// Just brings the app forward; the Dock-policy flip happens once Sparkle
    /// is about to show its update UI.
    @MainActor
    func checkForUpdates() {
        NSApp.activate(ignoringOtherApps: true)
        controller?.checkForUpdates(nil)
    }
}

extension UpdaterController: SPUUpdaterDelegate {}

extension UpdaterController: SPUStandardUserDriverDelegate {
    // Sparkle invokes user-driver callbacks on the main thread; `assumeIsolated`
    // hops onto the main actor without capturing `self`.
    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        MainActor.assumeIsolated { DockVisibilityCoordinator.shared.acquire() }
    }

    func standardUserDriverWillFinishUpdateSession() {
        MainActor.assumeIsolated { DockVisibilityCoordinator.shared.release() }
    }
}
