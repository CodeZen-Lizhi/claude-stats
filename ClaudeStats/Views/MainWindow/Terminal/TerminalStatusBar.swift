import Foundation
import GhosttyEmbed
import SwiftUI
import ClaudeStatsIconography

struct TerminalStatusBar: View {
    let tabs: [EmbeddedTerminalTabItem]
    let selectedTab: EmbeddedTerminalTabItem?
    let showsTabActions: Bool
    let onSelect: (UUID) -> Void
    let onNewTab: () -> Void
    let onCloseSelectedTab: () -> Void

    private var locationText: String {
        if let subtitle = selectedTab?.subtitle?.terminalAbbreviatedPath, !subtitle.isEmpty {
            return subtitle
        }
        return selectedTab?.title ?? "No terminal"
    }

    var body: some View {
        HStack(spacing: 10) {
            if showsTabActions {
                tabMenu
                statusDivider
            }

            HStack(spacing: 7) {
                FunctionalIconView(systemSymbolName: "folder")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(TerminalPalette.dimmed)
                    .frame(width: 14)
                Text(locationText)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(TerminalPalette.muted)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            if selectedTab?.needsAttention == true {
                HStack(spacing: 5) {
                    Circle().fill(TerminalPalette.accent).frame(width: 6, height: 6)
                    Text("Attention")
                        .font(.sora(10, weight: .medium))
                        .foregroundStyle(TerminalPalette.accent)
                }
            }

            Text("\(tabs.count) \(tabs.count == 1 ? "tab" : "tabs")")
                .font(.system(size: 11, weight: .medium, design: .monospaced).monospacedDigit())
                .foregroundStyle(TerminalPalette.dimmed)

            if showsTabActions {
                statusDivider
                Button(action: onNewTab) {
                    FunctionalIconView(systemSymbolName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .foregroundStyle(TerminalPalette.muted)
                .keyboardShortcut("t", modifiers: [.command])
                .help("New Terminal Tab")

                Button(action: onCloseSelectedTab) {
                    FunctionalIconView(systemSymbolName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .foregroundStyle(TerminalPalette.muted)
                .disabled(selectedTab == nil)
                .help("Close Current Tab")
            }
        }
        .frame(height: 32)
        .padding(.horizontal, 12)
        .background(Color.black.opacity(0.18))
    }

    private var tabMenu: some View {
        Menu {
            ForEach(tabs) { tab in
                Button {
                    onSelect(tab.id)
                } label: {
                    FunctionalLabel(tab.title, systemSymbolName: tab.id == selectedTab?.id ? "checkmark" : "terminal")
                }
            }

            Divider()

            Button("New Tab", action: onNewTab)
            Button("Close Current Tab", action: onCloseSelectedTab)
                .disabled(selectedTab == nil)
        } label: {
            HStack(spacing: 6) {
                FunctionalIconView(systemSymbolName: "terminal")
                Text("Terminal")
            }
            .font(.sora(11, weight: .medium))
            .foregroundStyle(TerminalPalette.text)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var statusDivider: some View {
        Rectangle()
            .fill(TerminalPalette.stroke)
            .frame(width: 1, height: 15)
    }
}

private extension String {
    var terminalAbbreviatedPath: String {
        let home = NSHomeDirectory()
        guard hasPrefix(home) else { return self }
        return "~" + dropFirst(home.count)
    }
}
