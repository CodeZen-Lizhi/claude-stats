import GhosttyEmbed
import SwiftUI

struct TerminalChromeView: View {
    @Environment(\.colorScheme) private var hostColorScheme

    @ObservedObject var store: EmbeddedTerminalStore
    let chromeMode: TerminalChromeMode
    let backgroundStyle: TerminalBackgroundStyle
    let onCloseTab: (EmbeddedTerminalTabItem) -> Void
    let onCloseSelectedTab: () -> Void

    private var selectedTab: EmbeddedTerminalTabItem? {
        store.tabs.first { $0.id == store.selectedTabID }
    }

    var body: some View {
        ZStack {
            TerminalBackdropView(style: backgroundStyle, colorScheme: hostColorScheme)

            VStack(spacing: 0) {
                if chromeMode.showsTopTabs {
                    TerminalTabStrip(
                        tabs: store.tabs,
                        selectedTabID: store.selectedTabID,
                        onSelect: { store.selectTab(id: $0) },
                        onClose: onCloseTab,
                        onNewTab: { store.addTab() }
                    )
                }

                terminalSurface

                if chromeMode.showsStatusBar {
                    TerminalStatusBar(
                        tabs: store.tabs,
                        selectedTab: selectedTab,
                        showsTabActions: !chromeMode.showsTopTabs,
                        onSelect: { store.selectTab(id: $0) },
                        onNewTab: { store.addTab() },
                        onCloseSelectedTab: onCloseSelectedTab
                    )
                }
            }
            .background(TerminalPalette.chromeBackground.opacity(0.92), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(TerminalPalette.stroke, lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.26), radius: 22, y: 14)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .terminalEntrance(cornerRadius: 8)
            .padding(14)
        }
        .environment(\.colorScheme, .dark)
        .background(Color.stxBackground)
    }

    private var terminalSurface: some View {
        ZStack {
            TerminalPalette.terminalBackground
            EmbeddedTerminalPaneView(store: store)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(TerminalPalette.stroke.opacity(0.72))
                .frame(height: 1)
                .opacity(chromeMode.showsTopTabs ? 1 : 0)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(TerminalPalette.stroke.opacity(0.72))
                .frame(height: 1)
                .opacity(chromeMode.showsStatusBar ? 1 : 0)
        }
    }
}
