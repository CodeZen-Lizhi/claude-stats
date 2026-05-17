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
    static let updateAvailabilityDidChange = Notification.Name("ClaudeStats.updateAvailabilityDidChange")

    private var controller: SPUStandardUpdaterController?
    private var dockVisibilityAcquired = false

    private(set) var updateAvailable = false
    private(set) var availableUpdateVersion: String?

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

    private func markUpdateAvailable(_ item: SUAppcastItem) {
        let version = item.displayVersionString.trimmingCharacters(in: .whitespacesAndNewlines)
        setUpdateAvailability(true, version: version.isEmpty ? nil : version)
    }

    private func clearUpdateAvailability() {
        setUpdateAvailability(false, version: nil)
    }

    private func setUpdateAvailability(_ available: Bool, version: String?) {
        guard updateAvailable != available || availableUpdateVersion != version else { return }
        updateAvailable = available
        availableUpdateVersion = version
        NotificationCenter.default.post(name: Self.updateAvailabilityDidChange, object: self)
    }

    private func acquireDockVisibilityForUpdateUI() {
        guard !dockVisibilityAcquired else { return }
        dockVisibilityAcquired = true
        MainActor.assumeIsolated { DockVisibilityCoordinator.shared.acquire() }
    }

    private func releaseDockVisibilityForUpdateUI() {
        guard dockVisibilityAcquired else { return }
        dockVisibilityAcquired = false
        MainActor.assumeIsolated { DockVisibilityCoordinator.shared.release() }
    }
}

extension UpdaterController: SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        markUpdateAvailable(item)
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        clearUpdateAvailability()
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        clearUpdateAvailability()
    }

    func updater(
        _ updater: SPUUpdater,
        userDidMake choice: SPUUserUpdateChoice,
        forUpdate updateItem: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        clearUpdateAvailability()
    }
}

extension UpdaterController: SPUStandardUserDriverDelegate {
    // Sparkle invokes user-driver callbacks on the main thread. Keep app-owned
    // state updates synchronous, and isolate only the AppKit dock-policy calls.
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        false
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        markUpdateAvailable(update)
        if handleShowingUpdate {
            acquireDockVisibilityForUpdateUI()
        }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        clearUpdateAvailability()
    }

    func standardUserDriverWillFinishUpdateSession() {
        clearUpdateAvailability()
        releaseDockVisibilityForUpdateUI()
    }
}
