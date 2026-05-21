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
    @Bindable var store: LinuxDoStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
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

            LinuxDoTopPeriodBar(store: store)
        }
        .padding(.horizontal, LinuxDoLayout.contentInset)
        .padding(.top, 50)
        .padding(.bottom, 16)
    }
}

private struct LinuxDoTopPeriodBar: View {
    @Bindable var store: LinuxDoStore

    var body: some View {
        HStack(spacing: 6) {
            ForEach(LinuxDoTopPeriod.allCases) { period in
                Button {
                    store.selectTopPeriod(period)
                } label: {
                    Label(period.displayName, systemImage: period.symbolName)
                        .font(.sora(11, weight: store.topPeriod == period ? .semibold : .medium))
                        .foregroundStyle(store.topPeriod == period ? Color.stxAccent : Color.stxMuted)
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background {
                            if store.topPeriod == period {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(Color.stxAccent.opacity(0.13))
                            }
                        }
                }
                .buttonStyle(.plain)
                .help("Top \(period.displayName)")
            }
        }
    }
}

private extension LinuxDoTopPeriod {
    var symbolName: String {
        switch self {
        case .daily:
            "sun.max"
        case .weekly:
            "calendar"
        case .monthly:
            "calendar.badge.clock"
        case .quarterly:
            "chart.bar.xaxis"
        case .yearly:
            "calendar.circle"
        case .all:
            "infinity"
        }
    }
}

#if DEBUG
#Preview("LinuxDo workspace") {
    LinuxDoWorkspaceView(store: AppEnvironment.preview().linuxDo)
        .environment(AppEnvironment.preview())
        .frame(width: 1040, height: 720)
}
#endif
