import SwiftUI

/// The main window's left column: brand header, custom nav rows grouped by
/// section, with Settings pinned to the bottom. Lives over a window-level
/// `NSVisualEffectView` (`.sidebar` material), so its own background stays
/// transparent and the system vibrancy shows through.
struct SidebarColumn: View {
    @Binding var page: MainPage
    var availablePages: [MainPage]
    var onOpenSettings: () -> Void
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Clear the traffic-light buttons (they float over the top-left
            // since the window uses `.hiddenTitleBar`).
            Color.clear.frame(height: 44)

            row(.dashboard)

            sectionHeader("STATS")
            row(.sessions)
            row(.usage)
            if env.preferences.aiActivityAnalysisEnabled { row(.activity) }
            if env.preferences.gitTrackingEnabled { row(.git) }

            Spacer(minLength: 0)

            SidebarRow(title: "Settings", symbol: "gearshape", isSelected: false, action: onOpenSettings)
        }
        .padding(.bottom, 10)
    }

    // MARK: - Section header

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.sora(10, weight: .semibold))
            .tracking(1.0)
            .foregroundStyle(Color.stxMuted)
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 4)
    }

    // MARK: - Row

    @ViewBuilder
    private func row(_ p: MainPage) -> some View {
        if availablePages.contains(p) {
            SidebarRow(title: p.title, symbol: p.symbol, isSelected: page == p) { page = p }
        }
    }
}

/// One sidebar nav row: an icon + label inside a rounded selection chip.
struct SidebarRow: View {
    let title: String
    let symbol: String
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 18)
                    .foregroundStyle(isSelected ? Color.stxAccent : Color.stxMuted)
                Text(title)
                    .font(.sora(13))
                    .foregroundStyle(isSelected ? .primary : Color.stxMuted)
                Spacer(minLength: 0)
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
        availablePages: [.dashboard, .sessions, .usage, .activity, .git],
        onOpenSettings: {}
    )
    .environment(AppEnvironment.preview())
    .frame(width: 220, height: 600)
    .background(VisualEffectBackground())
}
#endif
