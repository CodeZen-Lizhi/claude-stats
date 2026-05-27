import SwiftUI
import AppKit

struct AboutSettingsView: View {
    @Environment(AppEnvironment.self) private var env
    var onShowReleaseHistory: () -> Void = {}
    @State private var codexStatus = CodexVersionStatus.loading

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
}

private struct CodexVersionStatus: Equatable {
    var localVersion: String?
    var latestVersion: String?
    var localMessage: String
    var latestMessage: String

    static let loading = CodexVersionStatus(
        localVersion: nil,
        latestVersion: nil,
        localMessage: L10n.string("codex.version.checking", defaultValue: "Checking local Codex version..."),
        latestMessage: L10n.string("codex.version.checking_latest", defaultValue: "Checking latest release...")
    )

    var needsUpdate: Bool {
        guard let localVersion, let latestVersion else { return false }
        return localVersion != latestVersion
    }

    var statusLabel: String {
        guard localVersion != nil, latestVersion != nil else {
            return L10n.string("codex.version.unavailable", defaultValue: "Unavailable")
        }
        return L10n.string("codex.version.current", defaultValue: "Current")
    }

    var updateCommand: String {
        "npm install -g @openai/codex@latest"
    }
}

private struct CodexVersionChecker {
    func check() async -> CodexVersionStatus {
        async let local = localVersion()
        async let latest = latestVersion()
        let resolvedLocal = await local
        let resolvedLatest = await latest
        return CodexVersionStatus(
            localVersion: resolvedLocal.version,
            latestVersion: resolvedLatest.version,
            localMessage: resolvedLocal.message,
            latestMessage: resolvedLatest.message
        )
    }

    private func localVersion() async -> (version: String?, message: String) {
        await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["codex", "--version"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(decoding: data, as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard process.terminationStatus == 0 else {
                    return (nil, output.isEmpty ? "codex --version failed." : output)
                }
                return (Self.extractVersion(from: output), output)
            } catch {
                return (nil, error.localizedDescription)
            }
        }.value
    }

    private func latestVersion() async -> (version: String?, message: String) {
        do {
            let url = URL(string: "https://registry.npmjs.org/@openai/codex/latest")!
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return (nil, "npm registry returned an error.")
            }
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let version = object?["version"] as? String
            return (version, version ?? "No version field in npm latest metadata.")
        } catch {
            return (nil, error.localizedDescription)
        }
    }

    private static func extractVersion(from output: String) -> String? {
        output
            .split(whereSeparator: { !$0.isNumber && $0 != "." })
            .map(String.init)
            .first { $0.contains(".") }
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
