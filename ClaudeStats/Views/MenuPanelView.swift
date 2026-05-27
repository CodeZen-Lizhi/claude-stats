import SwiftUI
import AppKit

/// Which pane of the stats panel is shown.
enum StatsPane: String, CaseIterable, Identifiable {
    case sessions, usage, git
    var id: String { rawValue }
    var title: String {
        switch self {
        case .sessions: L10n.string("stats.pane.sessions", defaultValue: "Sessions")
        case .usage: L10n.string("stats.pane.usage", defaultValue: "Usage")
        case .git: L10n.string("stats.pane.git", defaultValue: "Git")
        }
    }
}

/// How much of the share timestamp to show in the exported panel's header
/// corner. Year + month are always shown; this picks the extra precision.
enum ExportStampPrecision: String, Hashable, CaseIterable, Identifiable {
    case monthOnly, day, minute
    var id: String { rawValue }
    var label: String {
        switch self {
        case .monthOnly: L10n.string("export.stamp.month", defaultValue: "Month")
        case .day: L10n.string("export.stamp.day", defaultValue: "Day")
        case .minute: L10n.string("export.stamp.time", defaultValue: "Time")
        }
    }
    func string(for date: Date) -> String {
        switch self {
        case .monthOnly: date.formatted(.dateTime.month(.abbreviated).year())
        case .day: date.formatted(.dateTime.month(.abbreviated).day().year())
        case .minute: date.formatted(.dateTime.month(.abbreviated).day().year().hour().minute())
        }
    }
}

/// Per-pane frozen state for an exported panel — the share window resolves all
/// of these and ``StatsPanelBody`` picks the one matching the selected pane.
struct StatsExportConfig {
    /// Usage pane settings. `.period` is also reused by the Sessions pane.
    var usage: UsageView.ExportConfig
    /// Whether the exported snapshot includes the top accent strip.
    var showTopBar: Bool = true
    /// The share timestamp shown in the header corner (replaces the live
    /// "UPD …" readout).
    var stampDate: Date = .now
    var stampPrecision: ExportStampPrecision = .monthOnly
}

/// The stats panel body: an accent strip, a header, a Sessions/Usage title bar
/// with a toggle, and the selected pane. Used both inside ``MenuPanelView`` (the
/// dropdown, which adds the Settings/Quit footer) and in the share-export window.
///
/// When `export` is non-nil the view is in "export" mode: the Usage pane's
/// period picker becomes a static label below the chart, the chart honours the
/// frozen style/scale from the config, the header's refresh control is hidden,
/// and the pane content takes
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
        if gitInPanel { panes.append(.git) }
        return panes
    }

    private var effectivePane: StatsPane {
        availablePanes.contains(pane) ? pane : .usage
    }

    private var effectivePaneBinding: Binding<StatsPane> {
        Binding(
            get: { effectivePane },
            set: { pane = $0 }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            if !isExport || (export?.showTopBar ?? true) {
                MenuPanelTopAccent(active: env.store.isLoading)
            }
            header
            StxRule()
            paneBar

            Group {
                switch effectivePane {
                case .sessions: SessionListView(mode: export.map { .export($0.usage.period) } ?? .interactive)
                case .usage: UsageView(mode: export.map { .export($0.usage) } ?? .interactive)
                case .git: GitActivityView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: isExport ? nil : .infinity)
        }
        .onChange(of: gitInPanel) { _, inPanel in
            if !inPanel && pane == .git { pane = .usage }
        }
    }

    private var paneBar: some View {
        HStack(spacing: 10) {
            Text(effectivePane.title)
                .font(.sora(18, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 8)
            PillSegmentedBar(
                availablePanes,
                selection: effectivePaneBinding,
                style: .toolbarModeSwitch
            ) { option, isSelected in
                Text(option.title)
                    .font(.sora(11, weight: isSelected ? .semibold : .medium))
                    .tracking(0.2)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text(L10n.format("stats.header.provider_stats",
                             defaultValue: "%@ Stats",
                             env.preferences.selectedProvider.shortName))
                .font(.sora(15, weight: .semibold))
                .foregroundStyle(.primary)
            Spacer()
            if let export {
                Text(export.stampPrecision.string(for: export.stampDate))
                    .font(.sora(9))
                    .tracking(0.5)
                    .foregroundStyle(Color.stxMuted)
            } else if let last = env.store.lastRefreshedAt {
                Text(L10n.format("stats.header.updated",
                                 defaultValue: "Updated %@",
                                 Format.relativeDate(last)))
                    .font(.sora(9))
                    .tracking(0.5)
                    .foregroundStyle(Color.stxMuted)
            }
            if !isExport && gitInWindow {
                MenuBarActionButton(
                    title: L10n.string("stats.action.git", defaultValue: "Git"),
                    systemImage: "arrow.triangle.branch"
                ) {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: GitActivityView.windowID)
                }
                .help(L10n.string("stats.action.git.help", defaultValue: "Open Git activity"))
            }
            if !isExport {
                MenuBarActionButton(
                    title: L10n.string("stats.action.refresh", defaultValue: "Refresh"),
                    systemImage: "arrow.clockwise",
                    isBusy: env.store.isLoading
                ) {
                    Task { await env.store.refresh() }
                }
                .disabled(env.store.isLoading)
                .help(L10n.string("stats.action.refresh.help", defaultValue: "Refresh now"))

                MenuBarActionButton(
                    title: L10n.string("stats.action.main", defaultValue: "Main"),
                    systemImage: "macwindow"
                ) {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: MainWindowView.windowID)
                }
                .help(L10n.string("stats.action.main.help", defaultValue: "Open the main window"))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

/// Root of the dropdown panel: the stats panel body plus a footer with
/// Settings / Share / Quit.
struct MenuPanelView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.openWindow) private var openWindow

    private static let panelSize = CGSize(width: 380, height: 560)

    @State private var pane: StatsPane = .usage
    @State private var updateAvailable = false
    @State private var availableUpdateVersion: String?

    var body: some View {
        VStack(spacing: 0) {
            StatsPanelBody(pane: $pane)
            StxRule()
            footer
        }
        .frame(width: Self.panelSize.width, height: Self.panelSize.height, alignment: .topLeading)
        .fixedSize(horizontal: true, vertical: true)
        .clipped()
        .background(VisualEffectBackground(material: .popover))
        .background(MenuPanelWindowSizeLock(size: Self.panelSize))
        .stxFont(13)
        .tint(.stxAccent)
        .onAppear(perform: syncUpdateAvailability)
        .onReceive(NotificationCenter.default.publisher(for: UpdaterController.updateAvailabilityDidChange)) { _ in
            syncUpdateAvailability()
        }
        .animation(.easeOut(duration: 0.16), value: updateAvailable)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            MenuBarActionButton(title: L10n.string("menu.footer.settings", defaultValue: "Settings"), systemImage: "gearshape") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: MainWindowView.windowID)
                NotificationCenter.default.post(name: .openSettingsInMainWindow, object: nil)
            }

            if updateAvailable {
                updateButton
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }

            MenuBarActionButton(title: L10n.string("menu.footer.share", defaultValue: "Share"), systemImage: "square.and.arrow.up") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: ShareExportView.windowID)
            }
            .help(L10n.string("menu.footer.share.help", defaultValue: "Export a snapshot as a PNG"))

            Spacer()
            MenuBarActionButton(title: L10n.string("menu.footer.quit", defaultValue: "Quit"), systemImage: "power") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .foregroundStyle(Color.stxMuted)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private var updateButton: some View {
        Button {
            env.updater.checkForUpdates()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 10, weight: .bold))
                Text(L10n.string("menu.footer.update", defaultValue: "Update"))
                    .font(.sora(10, weight: .semibold))
                    .lineLimit(1)
            }
            .tracking(0.2)
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(Color.stxAccent.opacity(0.14), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.stxAccent.opacity(0.58), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.stxAccent)
        .help(updateButtonHelp)
        .accessibilityLabel(updateButtonHelp)
    }

    private var updateButtonHelp: String {
        if let availableUpdateVersion {
            return L10n.format("menu.footer.update.install_version",
                               defaultValue: "Install update %@",
                               availableUpdateVersion)
        }
        return L10n.string("menu.footer.update.install", defaultValue: "Install update")
    }

    private func syncUpdateAvailability() {
        updateAvailable = env.updater.updateAvailable
        availableUpdateVersion = env.updater.availableUpdateVersion
    }
}

/// `MenuBarExtra` with `.window` derives its NSPanel size from SwiftUI's
/// preferred size on every interaction. The compact stats panel intentionally
/// contains flexible scroll/chart content, so we pin the host panel to the
/// product's fixed compact size and avoid a click-triggered resize feedback loop.
private struct MenuPanelWindowSizeLock: NSViewRepresentable {
    let size: CGSize

    func makeNSView(context: Context) -> LockView {
        let view = LockView()
        view.size = size
        return view
    }

    func updateNSView(_ nsView: LockView, context: Context) {
        nsView.size = size
        nsView.applySoon()
    }

    final class LockView: NSView {
        var size: CGSize = .zero
        private weak var lockedWindow: NSWindow?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            lockedWindow = window
            applySoon()
        }

        override func layout() {
            super.layout()
            applyIfNeeded()
        }

        func applySoon() {
            DispatchQueue.main.async { [weak self] in
                self?.applyIfNeeded()
            }
        }

        private func applyIfNeeded() {
            guard let window = window ?? lockedWindow, size != .zero else { return }
            lockedWindow = window
            let target = NSSize(width: size.width, height: size.height)
            if window.contentMinSize != target {
                window.contentMinSize = target
            }
            if window.contentMaxSize != target {
                window.contentMaxSize = target
            }
            guard let contentView = window.contentView else { return }
            let current = contentView.bounds.size
            if abs(current.width - target.width) > 0.5 || abs(current.height - target.height) > 0.5 {
                window.setContentSize(target)
            }
        }
    }
}

private struct MenuPanelTopAccent: View {
    let active: Bool

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(Color.stxAccent.opacity(active ? 0.75 : 0.28))
                .frame(height: 2)
            Circle()
                .fill(active ? Color.stxAccent : Color.stxStroke)
                .frame(width: 5, height: 5)
        }
        .padding(.horizontal, 12)
        .padding(.top, 9)
        .padding(.bottom, 6)
    }
}

private struct MenuBarActionButton: View {
    let title: String
    let systemImage: String
    var isBusy: Bool = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if isBusy {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 10, weight: .bold))
                }
                Text(title)
                    .font(.sora(10, weight: .semibold))
                    .lineLimit(1)
            }
            .tracking(0.2)
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(background, in: Capsule())
            .overlay(Capsule().strokeBorder(border, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(foreground)
        .onHover { hovering = $0 }
    }

    private var foreground: Color {
        hovering ? Color.primary : Color.stxMuted
    }

    private var background: Color {
        hovering ? Color.primary.opacity(0.06) : Color.primary.opacity(0.035)
    }

    private var border: Color {
        hovering ? Color.primary.opacity(0.12) : Color.stxStroke.opacity(0.75)
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
