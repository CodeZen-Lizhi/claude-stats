import SwiftUI
import AppKit

/// Which pane of the stats panel is shown.
enum StatsPane: String, CaseIterable, Identifiable {
    case sessions, usage, activity, git
    var id: String { rawValue }
    var title: String {
        switch self {
        case .sessions: "Sessions"
        case .usage: "Usage"
        case .activity: "Activity"
        case .git: "Git"
        }
    }
}

/// Per-pane frozen state for an exported panel — the share window resolves all
/// of these and ``StatsPanelBody`` picks the one matching the selected pane.
struct StatsExportConfig {
    /// Usage pane settings. `.period` is also reused by the Sessions pane.
    var usage: UsageView.ExportConfig
    var activity: AIActivityView.ExportData
}

/// The stats panel body: a scanline strip, a header, a Sessions/Usage title bar
/// with a toggle, and the selected pane. Used both inside ``MenuPanelView`` (the
/// dropdown, which adds the Settings/Quit footer) and in the share-export window.
///
/// When `export` is non-nil the view is in "export" mode: the Usage pane's
/// period picker becomes a static label below the chart, the chart honours the
/// frozen style/scale from the config, the Activity pane renders a pre-resolved
/// snapshot, the header's refresh control is hidden, and the pane content takes
/// its intrinsic height (so `ImageRenderer` captures the whole thing rather than
/// a clipped/scrolled slice).
struct StatsPanelBody: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.openWindow) private var openWindow
    @Binding var pane: StatsPane
    var export: StatsExportConfig? = nil

    private var isExport: Bool { export != nil }

    /// Git gets a pane only when tracking is on *and* the user wants it in-panel
    /// (otherwise it lives in its own window, opened from the header button).
    private var gitInPanel: Bool { env.preferences.gitTrackingEnabled && !env.preferences.gitOpensInWindow }
    private var gitInWindow: Bool { env.preferences.gitTrackingEnabled && env.preferences.gitOpensInWindow }

    private var availablePanes: [StatsPane] {
        var panes: [StatsPane] = [.sessions, .usage]
        if env.preferences.aiActivityAnalysisEnabled { panes.append(.activity) }
        if gitInPanel { panes.append(.git) }
        return panes
    }

    private var effectivePane: StatsPane {
        availablePanes.contains(pane) ? pane : .usage
    }

    var body: some View {
        VStack(spacing: 0) {
            if env.preferences.enabledProviders.count > 1 {
                ProviderSwitcherBar(interactive: !isExport)
            } else {
                TickBar(active: env.store.isLoading)
            }
            header
            StxRule()
            paneBar

            Group {
                switch effectivePane {
                case .sessions: SessionListView(mode: export.map { .export($0.usage.period) } ?? .interactive)
                case .usage: UsageView(mode: export.map { .export($0.usage) } ?? .interactive)
                case .activity: AIActivityView(mode: export.map { .export($0.activity) } ?? .interactive)
                case .git: GitActivityView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: isExport ? nil : .infinity)
        }
        .onChange(of: env.preferences.aiActivityAnalysisEnabled) { _, enabled in
            if !enabled && pane == .activity { pane = .usage }
        }
        .onChange(of: gitInPanel) { _, inPanel in
            if !inPanel && pane == .git { pane = .usage }
        }
    }

    private var paneBar: some View {
        HStack(spacing: 10) {
            Text(effectivePane.title.uppercased())
                .font(.sora(22, weight: .semibold))
                .tracking(2.5)
                .foregroundStyle(.primary)
            Spacer()
            HStack(spacing: 12) {
                ForEach(availablePanes) { p in
                    PaneChip(title: p.title, isSelected: p == effectivePane) { pane = p }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("\(env.preferences.selectedProvider.shortName.uppercased()) STATS")
                .font(.sora(15, weight: .semibold))
                .tracking(1.6)
                .foregroundStyle(.primary)
            Spacer()
            if let last = env.store.lastRefreshedAt {
                Text("UPD \(Format.relativeDate(last))".uppercased())
                    .font(.sora(9))
                    .tracking(0.5)
                    .foregroundStyle(Color.stxMuted)
            }
            if !isExport && gitInWindow {
                Button {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: GitActivityView.windowID)
                } label: {
                    BracketBox(spacing: 4) {
                        Image(systemName: "arrow.triangle.branch").font(.system(size: 10, weight: .bold))
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.stxMuted)
                .help("Open Git activity")
            }
            if !isExport {
                Button {
                    Task { await env.store.refresh() }
                } label: {
                    BracketBox(spacing: 4) {
                        if env.store.isLoading {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: "arrow.clockwise").font(.system(size: 10, weight: .bold))
                        }
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.stxMuted)
                .disabled(env.store.isLoading)
                .help("Refresh now")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

/// Root of the dropdown panel: the stats panel body plus a footer with
/// Settings / Share / Quit.
struct MenuPanelView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.openWindow) private var openWindow

    @State private var pane: StatsPane = .usage

    var body: some View {
        VStack(spacing: 0) {
            StatsPanelBody(pane: $pane)
            StxRule()
            footer
        }
        .frame(width: 380, height: 480)
        .font(.sora(13))
        .tint(.stxAccent)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            SettingsLink {
                BracketBox(spacing: 5) {
                    Label("SETTINGS", systemImage: "gearshape")
                        .labelStyle(.titleAndIcon)
                        .font(.sora(10))
                        .tracking(0.8)
                }
            }
            .buttonStyle(.plain)
            Button {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: ShareExportView.windowID)
            } label: {
                BracketBox(spacing: 5) {
                    Label("SHARE", systemImage: "square.and.arrow.up")
                        .labelStyle(.titleAndIcon)
                        .font(.sora(10))
                        .tracking(0.8)
                }
            }
            .buttonStyle(.plain)
            .help("Export a snapshot as a PNG")
            Spacer()
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                BracketBox(spacing: 5) {
                    Label("QUIT", systemImage: "power")
                        .labelStyle(.titleAndIcon)
                        .font(.sora(10))
                        .tracking(0.8)
                }
            }
            .buttonStyle(.plain)
            .keyboardShortcut("q")
        }
        .foregroundStyle(Color.stxMuted)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }
}

/// A small underlined tab chip used in the pane bar to switch panes.
private struct PaneChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Text(title.uppercased())
                    .font(.sora(10, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(isSelected ? .primary : (hovering ? Color.primary : Color.primary.opacity(0.40)))
                Rectangle()
                    .fill(Color.stxAccent)
                    .frame(height: 1.5)
                    .scaleEffect(x: isSelected ? 1 : 0, anchor: .center)
            }
            .fixedSize()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.18), value: isSelected)
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

#if DEBUG
#Preview("Panel") {
    MenuPanelView()
        .environment(AppEnvironment.preview())
}

#Preview("Panel — empty") {
    MenuPanelView()
        .environment(AppEnvironment.preview(populated: false))
}
#endif
