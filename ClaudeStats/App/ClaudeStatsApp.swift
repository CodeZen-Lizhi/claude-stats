import SwiftUI

@main
struct ClaudeStatsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuPanelView()
                .environment(appDelegate.env)
        } label: {
            MenuBarLabel()
                .environment(appDelegate.env)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(appDelegate.env)
        }
    }
}
