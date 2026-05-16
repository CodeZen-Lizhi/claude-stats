import GhosttyEmbed
import SwiftUI

struct TerminalWorkspaceView: View {
    @ObservedObject var store: EmbeddedTerminalStore
    @State private var pendingClose: EmbeddedTerminalTabItem?

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider().opacity(0.45)
            EmbeddedTerminalPaneView(store: store)
                .background(Color(nsColor: .textBackgroundColor))
        }
        .background(Color.stxBackground)
        .onAppear {
            store.ensureDefaultTab()
        }
        .confirmationDialog(
            "Close Terminal?",
            isPresented: Binding(
                get: { pendingClose != nil },
                set: { if !$0 { pendingClose = nil } }
            ),
            presenting: pendingClose
        ) { tab in
            Button("Close", role: .destructive) {
                _ = store.closeTab(id: tab.id, force: true)
                pendingClose = nil
            }
            Button("Cancel", role: .cancel) {
                pendingClose = nil
            }
        } message: { _ in
            Text("The terminal still has a running process. Closing it will kill the process.")
        }
    }

    private var tabBar: some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(store.tabs) { tab in
                        TerminalTabButton(
                            tab: tab,
                            isSelected: store.selectedTabID == tab.id,
                            onSelect: { store.selectTab(id: tab.id) },
                            onClose: { close(tab) }
                        )
                    }
                }
                .padding(.leading, 12)
                .padding(.vertical, 7)
            }

            Button {
                store.addTab()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.stxMuted)
                    .frame(width: 30, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("New Terminal Tab")
            .keyboardShortcut("t", modifiers: [.command])
            .padding(.trailing, 10)
        }
        .frame(height: 44)
        .background(Color.primary.opacity(0.045))
    }

    private func close(_ tab: EmbeddedTerminalTabItem) {
        if store.closeTab(id: tab.id, force: false) {
            pendingClose = nil
        } else {
            pendingClose = tab
        }
    }
}

private struct TerminalTabButton: View {
    let tab: EmbeddedTerminalTabItem
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 9) {
                Image(systemName: "terminal")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isSelected ? Color.primary : Color.stxMuted)

                Text(tab.title)
                    .font(.sora(13, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
                    .foregroundStyle(isSelected ? Color.primary : Color.stxMuted)

                if hovering || isSelected {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.stxMuted)
                            .frame(width: 16, height: 16)
                    }
                    .buttonStyle(.plain)
                    .help("Close Tab")
                }
            }
            .padding(.horizontal, 11)
            .frame(height: 30)
            .frame(minWidth: 128, maxWidth: 220, alignment: .leading)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(0.12))
                } else if hovering {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(0.06))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(tab.subtitle ?? tab.title)
    }
}

#if DEBUG
#Preview("Terminal workspace") {
    TerminalWorkspaceView(store: EmbeddedTerminalStore())
        .frame(width: 900, height: 560)
}
#endif
