import SwiftUI

private enum LinuxDoPaneMetrics {
    static let listMinWidth: CGFloat = 340
    static let detailMinWidth: CGFloat = 430
    static let detailConfiguration = HoverableSplitViewConfiguration(
        primaryMinimumPaneLength: listMinWidth,
        secondaryMinimumPaneLength: detailMinWidth
    )
}

struct LinuxDoWorkspaceView: View {
    @Bindable var store: LinuxDoStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LinuxDoHeader()
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

private struct LinuxDoHeader: View {
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
        }
        .padding(.horizontal, LinuxDoLayout.contentInset)
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
