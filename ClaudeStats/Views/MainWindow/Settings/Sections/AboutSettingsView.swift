import SwiftUI
import AppKit

struct AboutSettingsView: View {
    @Environment(AppEnvironment.self) private var env
    var onShowReleaseHistory: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            SettingGroup(title: "Data") {
                VStack(spacing: 0) {
                    SettingRow(title: "Codex config directory",
                               description: CodexPaths.default.homeDirectory.path) {
                        Button("Reveal in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([CodexPaths.default.homeDirectory])
                        }
                    }
                }
                .settingCard()
            }

            SettingGroup(title: "About") {
                VStack(spacing: 0) {
                    SettingRow(title: "Version",
                               description: appVersionString) {
                        Button("Check for Updates…") { env.updater.checkForUpdates() }
                    }
                    SettingRowDivider()
                    SettingRow(title: "Release History",
                               description: "See what changed since 1.4.0") {
                        Button("View…", action: onShowReleaseHistory)
                    }
                }
                .settingCard()
            }
        }
    }

    private var appVersionString: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }
}

#if DEBUG
#Preview {
    AboutSettingsView()
        .environment(AppEnvironment.preview())
        .padding()
        .frame(width: 720)
}
#endif
