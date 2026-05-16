import SwiftUI

/// Wide Usage page for the main window. The menu-bar panel still uses
/// `UsageView`; this view owns the larger-window layout and scene persistence.
struct MainUsageView: View {
    @Environment(AppEnvironment.self) private var env

    @SceneStorage("mainWindow.usage.period") private var periodRaw: String = StatsPeriod.allTime.rawValue
    @SceneStorage("mainWindow.usage.chartStyle") private var chartStyleRaw: String = MainUsageView.ChartStyleStorage.line.rawValue
    @SceneStorage("mainWindow.usage.scaleMode") private var scaleModeRaw: String = MainUsageView.ScaleModeStorage.linear.rawValue
    @SceneStorage("mainWindow.usage.stackByType") private var stackByTypeRaw: Bool = false

    @State private var vm = UsageViewModel()

    var body: some View {
        @Bindable var bvm = vm
        let provider = env.preferences.selectedProvider
        let summary = vm.summary(from: env.store, provider: provider)
        let series = summary.trendSeries()
        let includeCache = env.preferences.includeCacheInTokens
        let cacheHitRate = env.store.cacheHitRate(for: summary.totalUsage, provider: provider)

        FadingScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header(provider: provider)
                controls(period: $bvm.period)
                UsageSummaryCards(
                    summary: summary,
                    includeCacheInTokens: includeCache,
                    cacheHitRate: cacheHitRate
                )
                UsageTrendPanel(
                    series: series,
                    chartStyle: $bvm.chartStyle,
                    scaleMode: $bvm.scaleMode,
                    stackByType: $bvm.stackByType,
                    displayName: modelDisplayName
                )
                lowerPanels(summary: summary, series: series, includeCache: includeCache, cacheHitRate: cacheHitRate)
            }
            .padding(.horizontal, 20)
            .padding(.top, 52)
            .padding(.bottom, 22)
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .onAppear(perform: syncFromSceneStorage)
        .onChange(of: vm.period) { _, new in periodRaw = new.rawValue }
        .onChange(of: vm.chartStyle) { _, new in chartStyleRaw = ChartStyleStorage(new).rawValue }
        .onChange(of: vm.scaleMode) { _, new in scaleModeRaw = ScaleModeStorage(new).rawValue }
        .onChange(of: vm.stackByType) { _, new in stackByTypeRaw = new }
    }

    private func header(provider: ProviderKind) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("USAGE")
                .font(.sora(11, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(Color.stxMuted)
            Text("Token usage")
                .font(.sora(24, weight: .semibold))
                .lineLimit(1)
            Text("Cost, cache, and model mix for \(provider.displayName).")
                .font(.sora(12))
                .foregroundStyle(Color.stxMuted)
                .lineLimit(1)
        }
    }

    private func controls(period: Binding<StatsPeriod>) -> some View {
        HStack(alignment: .center, spacing: 12) {
            UsagePeriodChips(period: period)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func lowerPanels(summary: UsageSummary, series: TrendSeries, includeCache: Bool, cacheHitRate: Double?) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) {
                UsageModelBreakdown(
                    models: summary.models,
                    series: series,
                    includeCacheInTokens: includeCache,
                    displayName: modelDisplayName
                )
                .frame(minWidth: 560, maxWidth: .infinity)

                UsageTokenCompositionPanel(
                    usage: summary.totalUsage,
                    includeCacheInTokens: includeCache,
                    cacheHitRate: cacheHitRate
                )
                .frame(width: 300)
            }

            VStack(alignment: .leading, spacing: 12) {
                UsageModelBreakdown(
                    models: summary.models,
                    series: series,
                    includeCacheInTokens: includeCache,
                    displayName: modelDisplayName
                )
                UsageTokenCompositionPanel(
                    usage: summary.totalUsage,
                    includeCacheInTokens: includeCache,
                    cacheHitRate: cacheHitRate
                )
            }
        }
    }

    private func syncFromSceneStorage() {
        vm.period = StatsPeriod(rawValue: periodRaw) ?? .allTime
        vm.chartStyle = ChartStyleStorage(rawValue: chartStyleRaw)?.chartStyle ?? .line
        vm.scaleMode = ScaleModeStorage(rawValue: scaleModeRaw)?.scaleMode ?? .linear
        vm.stackByType = stackByTypeRaw
    }

    private func modelDisplayName(_ id: String) -> String {
        env.store.displayName(forModel: id, provider: env.preferences.selectedProvider)
    }
}

private struct UsagePeriodChips: View {
    @Binding var period: StatsPeriod

    private static let values: [StatsPeriod] = [.today, .last7Days, .last30Days, .allTime]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Self.values) { value in
                chip(value)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
    }

    private func chip(_ value: StatsPeriod) -> some View {
        let selected = period == value
        return Button {
            withAnimation(.easeOut(duration: 0.18)) { period = value }
        } label: {
            Text(label(for: value))
                .font(.sora(11, weight: .medium))
                .foregroundStyle(selected ? .primary : Color.stxMuted)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background {
                    if selected {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.stxPanel)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(Color.stxStroke, lineWidth: 1)
                            )
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(value.displayName)
    }

    private func label(for period: StatsPeriod) -> String {
        switch period {
        case .today: "Today"
        case .last7Days: "7d"
        case .last30Days: "30d"
        case .allTime: "All"
        }
    }
}

private extension MainUsageView {
    enum ChartStyleStorage: String {
        case line, bar

        init(_ chartStyle: TrendChartStyle) {
            self = chartStyle == .line ? .line : .bar
        }

        var chartStyle: TrendChartStyle {
            switch self {
            case .line: .line
            case .bar: .bar
            }
        }
    }

    enum ScaleModeStorage: String {
        case linear, log

        init(_ scaleMode: TrendScaleMode) {
            self = scaleMode == .linear ? .linear : .log
        }

        var scaleMode: TrendScaleMode {
            switch self {
            case .linear: .linear
            case .log: .log
            }
        }
    }
}

extension View {
    func mainUsagePanel(padding: CGFloat = 14) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.stxPanel, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.stxStroke, lineWidth: 1))
    }
}

#if DEBUG
#Preview("Main Usage") {
    MainUsageView()
        .environment(AppEnvironment.preview())
        .frame(width: 1040, height: 720)
        .background(Color.stxBackground)
}
#endif
