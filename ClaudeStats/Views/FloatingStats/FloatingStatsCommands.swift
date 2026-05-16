import AppKit
import SwiftUI

extension Notification.Name {
    static let openMainWindowFromFloatingStats = Notification.Name("ClaudeStats.openMainWindowFromFloatingStats")
    static let openSettingsFromFloatingStats = Notification.Name("ClaudeStats.openSettingsFromFloatingStats")
}

/// Bridges AppKit-owned floating-panel commands back into SwiftUI's scene
/// system, where `openWindow` is available.
struct FloatingStatsCommandBridge: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onReceive(NotificationCenter.default.publisher(for: .openMainWindowFromFloatingStats)) { _ in
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: MainWindowView.windowID)
            }
            .onReceive(NotificationCenter.default.publisher(for: .openSettingsFromFloatingStats)) { _ in
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: MainWindowView.windowID)
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .openSettingsInMainWindow, object: nil)
                }
            }
    }
}
