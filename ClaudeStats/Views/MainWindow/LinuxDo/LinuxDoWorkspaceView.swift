import AppKit
import SwiftUI

private enum LinuxDoPaneMetrics {
    static let sourceMinWidth: CGFloat = 210
    static let listMinWidth: CGFloat = 340
    static let detailMinWidth: CGFloat = 430
    static let secondaryMinWidth = listMinWidth + detailMinWidth

    static let outerConfiguration = HoverableSplitViewConfiguration(
        primaryMinimumPaneLength: sourceMinWidth,
        secondaryMinimumPaneLength: secondaryMinWidth
    )
    static let detailConfiguration = HoverableSplitViewConfiguration(
        primaryMinimumPaneLength: listMinWidth,
        secondaryMinimumPaneLength: detailMinWidth
    )
}

struct LinuxDoWorkspaceView: View {
    @Bindable var store: LinuxDoStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LinuxDoHeader(store: store)
            StxRule()
            workspace
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task {
            await store.loadInitialIfNeeded()
        }
    }

    private var workspace: some View {
        HoverableSplitView(
            axis: .vertical,
            primaryFraction: 0.22,
            configuration: LinuxDoPaneMetrics.outerConfiguration
        ) {
            LinuxDoSourceColumn(store: store)
                .frame(minWidth: 0, idealWidth: 230, maxWidth: .infinity, maxHeight: .infinity)
        } secondary: {
            HoverableSplitView(
                axis: .vertical,
                primaryFraction: 0.42,
                configuration: LinuxDoPaneMetrics.detailConfiguration
            ) {
                LinuxDoTopicListView(store: store)
                    .frame(minWidth: 0, idealWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
            } secondary: {
                LinuxDoTopicDetailView(store: store)
                    .frame(minWidth: 0, idealWidth: 560, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

private struct LinuxDoHeader: View {
    @Bindable var store: LinuxDoStore

    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("COMMUNITY")
                    .font(.sora(11, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(Color.stxMuted)
                Text("LinuxDo")
                    .font(.sora(24, weight: .semibold))
                Text("Browse Linux.do topics with a native macOS reader.")
                    .font(.sora(12))
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                if store.currentListState.isRefreshing || store.isLoadingCategories {
                    ProgressView()
                        .controlSize(.small)
                }
                Button {
                    Task { await store.refreshCurrentFeed() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .controlSize(.small)
                .disabled(store.currentListState.isLoading || store.currentListState.isRefreshing)

                Button {
                    NSWorkspace.shared.open(URL(string: "https://linux.do")!)
                } label: {
                    Label("Open", systemImage: "safari")
                }
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 50)
        .padding(.bottom, 16)
    }
}

#if DEBUG
#Preview("LinuxDo workspace") {
    LinuxDoWorkspaceView(store: AppEnvironment.preview().linuxDo)
        .environment(AppEnvironment.preview())
        .frame(width: 1040, height: 720)
}
#endif

