import SwiftUI
import AppKit

/// The main window's left column. Two regions stacked vertically:
///   - Top nav (Dashboard, STATS for usage/leaderboards/activity, then TOOLS
///     for configuration, Git, and terminal tools).
/// Settings stays pinned at the bottom.
///
/// Lives over a window-level `NSVisualEffectView` (`.sidebar` material), so
/// its own background stays transparent.
struct SidebarColumn: View {
    @Binding var page: MainPage
    var availablePages: [MainPage]
    var onOpenSettings: () -> Void
    var onOpenLinuxDo: () -> Void
    var onOpenSessions: () -> Void
    var onOpenConfigs: () -> Void
    var onOpenNetwork: () -> Void
    var onOpenOps: () -> Void

    @Environment(AppEnvironment.self) private var env

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Clear the traffic-light buttons (window uses `.hiddenTitleBar`).
            Color.clear.frame(height: 44)

            navRow(.dashboard)
            SidebarRow(
                title: MainPage.linuxDo.title,
                symbol: MainPage.linuxDo.symbol,
                isSelected: false,
                trailingSymbol: "chevron.right",
                showsTrailingOnHover: true
            ) {
                clearTextFocus()
                onOpenLinuxDo()
            }
            sessionsEntryRow

            sectionHeader("STATS")
            navRow(.usage)
            navRow(.leaderboards)
            if env.preferences.aiActivityAnalysisEnabled { navRow(.activity) }
            if env.preferences.systemMonitorEnabled { navRow(.system) }

            sectionHeader("TOOLS")
            navRow(.configurations)
            SidebarRow(
                title: "Configs",
                symbol: "doc.text.magnifyingglass",
                isSelected: false,
                trailingSymbol: "chevron.right",
                showsTrailingOnHover: true
            ) {
                clearTextFocus()
                onOpenConfigs()
            }
            if env.preferences.gitTrackingEnabled { navRow(.git) }
            navRow(.skills)
            SidebarRow(
                title: "Ops",
                symbol: "wrench.and.screwdriver",
                isSelected: false,
                trailingSymbol: "chevron.right",
                showsTrailingOnHover: true
            ) {
                clearTextFocus()
                onOpenOps()
            }
            SidebarRow(
                title: "Network",
                symbol: "network",
                isSelected: false,
                trailingSymbol: "chevron.right",
                showsTrailingOnHover: true
            ) {
                clearTextFocus()
                onOpenNetwork()
            }
            navRow(.terminal)

            Spacer(minLength: 0)

            SidebarRow(title: "Settings", symbol: "gearshape", isSelected: false) {
                clearTextFocus()
                onOpenSettings()
            }
        }
        .padding(.bottom, 10)
        .background {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { clearTextFocus() }
        }
    }

    // MARK: - Top nav

    @ViewBuilder
    private func navRow(_ p: MainPage) -> some View {
        if availablePages.contains(p) {
            SidebarRow(
                title: p.title,
                symbol: p.symbol,
                isSelected: page == p
            ) {
                clearTextFocus()
                page = p
            }
        }
    }

    private var sessionsEntryRow: some View {
        let count = env.store.sessions(for: env.preferences.selectedProvider).count
        return SidebarRow(
            title: "Sessions",
            symbol: "text.bubble",
            isSelected: false,
            trailingText: count > 0 ? "\(count)" : nil,
            trailingSymbol: "chevron.right",
            showsTrailingOnHover: true
        ) {
            clearTextFocus()
            onOpenSessions()
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(LocalizedStringKey(title))
            .font(.sora(10, weight: .semibold))
            .tracking(1.0)
            .foregroundStyle(Color.stxMuted)
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 4)
    }

    private func clearTextFocus() {
        NSApp.keyWindow?.makeFirstResponder(nil)
    }
}

// MARK: - Top nav row

/// One sidebar nav row: an icon + label inside a rounded selection chip.
struct SidebarRow: View {
    let title: String
    let symbol: String
    let isSelected: Bool
    var trailingText: String? = nil
    var trailingSymbol: String?
    var showsTrailingOnHover = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 18)
                    .foregroundStyle(isSelected ? Color.stxAccent : Color.stxMuted)
                Text(LocalizedStringKey(title))
                    .font(.sora(13))
                    .foregroundStyle(isSelected ? .primary : Color.stxMuted)
                Spacer(minLength: 0)
                if let trailingText {
                    Text(trailingText)
                        .font(.sora(9).monospacedDigit())
                        .foregroundStyle(isSelected ? Color.stxAccent : Color.stxMuted)
                        .lineLimit(1)
                }
                if let trailingSymbol {
                    Image(systemName: trailingSymbol)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(isSelected ? Color.stxAccent : Color.stxMuted)
                        .opacity(showsTrailingOnHover ? (hovering ? 1 : 0) : 1)
                        .frame(width: 12)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.10))
                } else if hovering {
                    RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .padding(.vertical, 1)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isSelected)
    }
}

#if DEBUG
#Preview("Sidebar column") {
    @Previewable @State var page: MainPage = .dashboard
    return SidebarColumn(
        page: $page,
        availablePages: [.dashboard, .configurations, .usage, .activity, .git],
        onOpenSettings: {},
        onOpenLinuxDo: {},
        onOpenSessions: {},
        onOpenConfigs: {},
        onOpenNetwork: {},
        onOpenOps: {}
    )
    .environment(AppEnvironment.preview())
    .frame(width: 240, height: 600)
    .background(VisualEffectBackground())
}
#endif
