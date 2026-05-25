import AppKit
import SwiftUI

extension Notification.Name {
    static let openMainWindowOnAppLaunch = Notification.Name("ClaudeStats.openMainWindowOnAppLaunch")
}

/// Gives AppKit launch code a SwiftUI `openWindow` bridge for the main window.
struct MainWindowLaunchBridge: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.openWindow) private var openWindow
    @State private var didRequestOpen = false

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear(perform: openMainWindowIfNeeded)
            .onReceive(NotificationCenter.default.publisher(for: .openMainWindowOnAppLaunch)) { _ in
                openMainWindowIfNeeded()
            }
    }

    private func openMainWindowIfNeeded() {
        guard env.preferences.openMainWindowOnLaunch, !didRequestOpen else { return }
        didRequestOpen = true

        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: MainWindowView.windowID)
        }
    }
}
