import AppKit
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
        let costMode = env.preferences.costEstimationMode
        let cacheHitRate = env.store.cacheHitRate(for: summary.totalUsage, provider: provider)

        FadingScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header(provider: provider)
                controls(period: $bvm.period)
                UsageSummaryCards(
                    summary: summary,
                    includeCacheInTokens: includeCache,
                    costEstimationMode: costMode,
                    cacheHitRate: cacheHitRate
                )
                if provider.supportsUsageLimits {
                    usageLimitPanel(provider: provider)
                }
                UsageTrendPanel(
                    series: series,
                    rangeID: vm.period.rawValue,
                    chartStyle: $bvm.chartStyle,
                    scaleMode: $bvm.scaleMode,
                    stackByType: $bvm.stackByType,
                    displayName: modelDisplayName
                )
                lowerPanels(summary: summary, series: series, includeCache: includeCache, costMode: costMode, cacheHitRate: cacheHitRate)
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
        .onChange(of: env.store.lastRefreshedAt) { _, _ in
            guard env.preferences.selectedProvider.supportsUsageLimits else { return }
            Task {
                await env.usageLimits.refresh(provider: env.preferences.selectedProvider, force: true)
            }
        }
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

    private func usageLimitPanel(provider: ProviderKind) -> some View {
        UsageLimitPanel(
            provider: provider,
            report: env.usageLimits.report(for: provider),
            isLoading: env.usageLimits.isLoading(provider),
            actionMessage: env.usageLimits.actionMessage(for: provider),
            onRefresh: {
                Task { await env.usageLimits.refresh(provider: provider, force: true) }
            },
            onInstallClaudeBridge: provider == .claude ? {
                env.usageLimits.installClaudeBridge()
            } : nil,
            onCopyClaudeSettingsSnippet: provider == .claude ? {
                copyClaudeSettingsSnippet()
            } : nil,
            onOpenClaudeSettings: provider == .claude ? {
                openClaudeSettings()
            } : nil
        )
        .task(id: provider) {
            await env.usageLimits.refresh(provider: provider)
        }
    }

    @ViewBuilder
    private func lowerPanels(summary: UsageSummary, series: TrendSeries, includeCache: Bool, costMode: CostEstimationMode, cacheHitRate: Double?) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) {
                UsageModelBreakdown(
                    models: summary.models,
                    series: series,
                    includeCacheInTokens: includeCache,
                    costEstimationMode: costMode,
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
                    costEstimationMode: costMode,
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

    private func copyClaudeSettingsSnippet() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(env.usageLimits.claudeSettingsSnippet(), forType: .string)
        env.usageLimits.recordActionMessage("Claude settings snippet copied.", for: .claude)
    }

    private func openClaudeSettings() {
        NSWorkspace.shared.open(env.usageLimits.claudeSettingsURL())
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
            period = value
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
        .animation(UsageTrendMotion.periodChip, value: selected)
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
        mainWindowPanel(padding: padding)
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
