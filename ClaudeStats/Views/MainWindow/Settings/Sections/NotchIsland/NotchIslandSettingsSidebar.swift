import SwiftUI

struct NotchIslandSettingsSidebar: View {
    @Binding var selection: NotchIslandSettingsTab
    let enabledModules: Set<NotchIslandModule>

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AppScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(NotchIslandSettingsTab.grouped, id: \.group) { section in
                        if let title = section.group.title {
                            Text(title)
                                .font(.sora(9, weight: .semibold))
                                .tracking(0.9)
                                .foregroundStyle(Color.stxMuted)
                                .padding(.horizontal, 16)
                                .padding(.top, 14)
                                .padding(.bottom, 5)
                        }

                        ForEach(section.tabs) { tab in
                            NotchIslandSidebarRow(
                                tab: tab,
                                isSelected: selection == tab,
                                isEnabled: tab.module.map(enabledModules.contains) ?? true
                            ) {
                                selection = tab
                            }
                        }
                    }
                }
                .padding(.bottom, 14)
            }
        }
    }
}

private struct NotchIslandSidebarRow: View {
    let tab: NotchIslandSettingsTab
    let isSelected: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(iconForeground)
                    .frame(width: 26, height: 26)
                    .background(iconBackground, in: RoundedRectangle(cornerRadius: 7, style: .continuous))

                Text(tab.title)
                    .font(.sora(12, weight: isSelected ? .semibold : .medium))
                    .lineLimit(1)
                    .foregroundStyle(rowForeground)

                Spacer(minLength: 0)

                if !isEnabled {
                    Circle()
                        .fill(Color.stxMuted.opacity(0.35))
                        .frame(width: 6, height: 6)
                        .help("Module is disabled")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(rowBackground)
        }
        .buttonStyle(.plain)
        .padding(.trailing, 8)
    }

    private var iconForeground: Color {
        if isSelected { return Color.white }
        return isEnabled ? Color.primary : Color.stxMuted
    }

    private var rowForeground: Color {
        if isSelected { return Color.primary }
        return isEnabled ? Color.primary.opacity(0.86) : Color.stxMuted
    }

    private var iconBackground: some ShapeStyle {
        isSelected ? Color.stxAccent : Color.primary.opacity(isEnabled ? 0.07 : 0.035)
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(isSelected ? Color.primary.opacity(0.08) : Color.clear)
    }
}
