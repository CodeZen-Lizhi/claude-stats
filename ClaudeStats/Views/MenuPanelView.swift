import SwiftUI
import AppKit

/// Which pane of the stats panel is shown.
enum StatsPane: String, CaseIterable, Identifiable {
    case sessions, usage
    var id: String { rawValue }
    var title: String { self == .sessions ? "Sessions" : "Usage" }
    var toggled: StatsPane { self == .sessions ? .usage : .sessions }
}

/// The stats panel body: a scanline strip, a header, a Sessions/Usage title bar
/// with a toggle, and the selected pane. Used both inside ``MenuPanelView`` (the
/// dropdown, which adds the Settings/Quit footer) and in the share-export window.
///
/// When `exportConfig` is non-nil the view is in "export" mode: the Usage pane's
/// period picker becomes a static label below the chart, the chart honours the
/// frozen style/scale from the config, the header's refresh control is hidden,
/// and the pane content takes its intrinsic height (so `ImageRenderer` captures
/// the whole thing rather than a clipped/scrolled slice).
struct StatsPanelBody: View {
    @Environment(AppEnvironment.self) private var env
    @Binding var pane: StatsPane
    var exportConfig: UsageView.ExportConfig? = nil

    private var isExport: Bool { exportConfig != nil }

    var body: some View {
        VStack(spacing: 0) {
            TickBar(active: env.store.isLoading)
            header
            StxRule()
            paneBar

            Group {
                switch pane {
                case .sessions: SessionListView(mode: exportConfig.map { .export($0.period) } ?? .interactive)
                case .usage: UsageView(mode: exportConfig.map(UsageView.Mode.export) ?? .interactive)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: isExport ? nil : .infinity)
        }
    }

    private var paneBar: some View {
        HStack(spacing: 10) {
            Text(pane.title.uppercased())
                .font(.sora(22, weight: .semibold))
                .tracking(2.5)
                .foregroundStyle(.primary)
            Spacer()
            Button {
                pane = pane.toggled
            } label: {
                BracketBox(spacing: 5) {
                    Label(pane.toggled.title.uppercased(), systemImage: "arrow.left.arrow.right")
                        .labelStyle(.titleAndIcon)
                        .font(.sora(10))
                        .tracking(0.8)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.stxMuted)
            .help("Switch to \(pane.toggled.title)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("CLAUDE STATS")
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
