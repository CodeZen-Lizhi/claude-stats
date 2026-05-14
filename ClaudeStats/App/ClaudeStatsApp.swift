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

        Window("Share Stats", id: ShareExportView.windowID) {
            ShareExportView()
                .environment(appDelegate.env)
        }
        .windowResizability(.contentSize)

        Window("Git Activity", id: GitActivityView.windowID) {
            GitActivityView()
                .environment(appDelegate.env)
                .frame(minWidth: 460, idealWidth: 520, minHeight: 480, idealHeight: 640)
                .font(.sora(13))
                .tint(.stxAccent)
        }

        Window("Claude Stats", id: MainWindowView.windowID) {
            MainWindowView()
                .environment(appDelegate.env)
                .frame(minWidth: 880, idealWidth: 1040, minHeight: 600, idealHeight: 720)
                .font(.sora(13))
                .tint(.stxAccent)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
    }
}
