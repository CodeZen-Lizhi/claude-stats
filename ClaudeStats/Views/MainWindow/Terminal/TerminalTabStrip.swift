import GhosttyEmbed
import SwiftUI

struct TerminalTabStrip: View {
    let tabs: [EmbeddedTerminalTabItem]
    let selectedTabID: UUID?
    let onSelect: (UUID) -> Void
    let onClose: (EmbeddedTerminalTabItem) -> Void
    let onNewTab: () -> Void

    @Namespace private var activeTabNamespace

    var body: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(tabs) { tab in
                        TerminalTabButton(
                            tab: tab,
                            isSelected: selectedTabID == tab.id,
                            namespace: activeTabNamespace,
                            onSelect: { onSelect(tab.id) },
                            onClose: { onClose(tab) }
                        )
                    }
                }
                .padding(.leading, 10)
                .padding(.vertical, 7)
            }

            Button(action: onNewTab) {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(TerminalPalette.muted)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("New Terminal Tab")
            .keyboardShortcut("t", modifiers: [.command])
            .padding(.trailing, 10)
        }
        .frame(height: 46)
        .background {
            LinearGradient(
                colors: [
                    Color.white.opacity(0.075),
                    Color.white.opacity(0.030),
                    Color.black.opacity(0.040),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

private struct TerminalTabButton: View {
    let tab: EmbeddedTerminalTabItem
    let isSelected: Bool
    let namespace: Namespace.ID
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 7) {
            Button(action: onSelect) {
                HStack(spacing: 8) {
                    Image(systemName: "terminal")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(iconColor)
                        .frame(width: 14)

                    Text(tab.title)
                        .font(.system(size: 13, weight: isSelected ? .semibold : .regular, design: .monospaced))
                        .lineLimit(1)
                        .foregroundStyle(isSelected ? TerminalPalette.text : TerminalPalette.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if tab.needsAttention {
                        Circle()
                            .fill(TerminalPalette.accent)
                            .frame(width: 6, height: 6)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(hovering || isSelected ? TerminalPalette.muted : .clear)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Close Tab")
            .disabled(!(hovering || isSelected))
            .opacity(hovering || isSelected ? 1 : 0.001)
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .frame(width: 178, height: 31, alignment: .leading)
        .background(background)
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onHover { hovering = $0 }
        .help(tab.subtitle ?? tab.title)
        .animation(.easeOut(duration: 0.14), value: hovering)
        .animation(.easeOut(duration: 0.16), value: isSelected)
    }

    private var iconColor: Color {
        if tab.needsAttention { return TerminalPalette.accent }
        return isSelected ? TerminalPalette.text : TerminalPalette.dimmed
    }

    @ViewBuilder
    private var background: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(TerminalPalette.chromeRaised)
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.075), lineWidth: 1)
                }
                .matchedGeometryEffect(id: "activeTerminalTab", in: namespace)
        } else if hovering {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.055))
        }
    }
}
