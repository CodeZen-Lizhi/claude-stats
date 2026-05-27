import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct AboutSettingsView: View {
    @Environment(AppEnvironment.self) private var env
    var onShowReleaseHistory: () -> Void = {}
    @State private var codexStatus = CodexVersionStatus.loading
    @State private var diagnosticsMessage: String?
    @State private var diagnosticsIsExporting = false

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

            SettingGroup(title: "Codex Version") {
                VStack(spacing: 0) {
                    SettingRow(title: "Local Codex",
                               description: codexStatus.localVersion ?? codexStatus.localMessage) {
                        Button("Refresh") {
                            Task { await refreshCodexStatus() }
                        }
                    }
                    SettingRowDivider()
                    SettingRow(title: "Latest Codex",
                               description: codexStatus.latestVersion ?? codexStatus.latestMessage) {
                        if codexStatus.needsUpdate {
                            Button("Copy update command") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(codexStatus.updateCommand, forType: .string)
                            }
                        } else {
                            Text(codexStatus.statusLabel)
                                .font(.sora(11, weight: .medium))
                                .foregroundStyle(Color.stxMuted)
                        }
                    }
                }
                .settingCard()
            }

            SettingGroup(title: "Diagnostics") {
                VStack(spacing: 0) {
                    SettingRow(title: "Export diagnostics",
                               description: diagnosticsMessage ?? "Creates a redacted support bundle with logs, scanner status, permissions, and integration health.") {
                        Button(diagnosticsIsExporting ? "Exporting..." : "Export…") {
                            exportDiagnostics()
                        }
                        .disabled(diagnosticsIsExporting)
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
        .task { await refreshCodexStatus() }
    }

    private var appVersionString: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }

    @MainActor
    private func refreshCodexStatus() async {
        codexStatus = .loading
        codexStatus = await CodexVersionChecker().check()
    }

    private func exportDiagnostics() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.zip]
        panel.canCreateDirectories = true
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        panel.nameFieldStringValue = "Codex Statistics Diagnostics \(formatter.string(from: .now)).zip"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        diagnosticsIsExporting = true
        diagnosticsMessage = nil
        Task { @MainActor in
            do {
                let exported = try await DiagnosticsExporter().export(environment: env, to: url)
                diagnosticsMessage = "Saved \(exported.lastPathComponent)."
            } catch {
                diagnosticsMessage = "Export failed: \(error.localizedDescription)"
            }
            diagnosticsIsExporting = false
        }
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
