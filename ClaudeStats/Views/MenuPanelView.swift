import SwiftUI
import AppKit

/// Root of the dropdown panel: a header, a Sessions/Usage switcher, the
/// selected pane, and a footer with Settings / Quit.
struct MenuPanelView: View {
    @Environment(AppEnvironment.self) private var env

    private enum Pane: String, CaseIterable, Identifiable {
        case sessions, usage
        var id: String { rawValue }
        var title: String { self == .sessions ? "Sessions" : "Usage" }
    }
    @State private var pane: Pane = .sessions

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Picker("", selection: $pane) {
                ForEach(Pane.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(8)

            Group {
                switch pane {
                case .sessions: SessionListView()
                case .usage: UsageView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            footer
        }
        .frame(width: 380, height: 480)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "chart.bar.xaxis")
                .foregroundStyle(.tint)
            Text("Claude Stats").font(.headline)
            Spacer()
            if let last = env.store.lastRefreshedAt {
                Text("Updated \(Format.relativeDate(last))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Button {
                Task { await env.store.refresh() }
            } label: {
                if env.store.isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.borderless)
            .disabled(env.store.isLoading)
            .help("Refresh now")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var footer: some View {
        HStack {
            SettingsLink {
                Label("Settings…", systemImage: "gearshape")
            }
            .buttonStyle(.borderless)
            Spacer()
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("q")
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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
