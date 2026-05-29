import SwiftUI

/// The status-item content: an icon plus a compact tokens-or-cost figure for
/// the configured period.
struct MenuBarLabel: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let prefs = env.preferences
        let summary = env.store.summary(for: prefs.menuBarPeriod, provider: prefs.selectedProvider)
        let value = valueText(summary: summary, metric: prefs.menuBarMetric)
        HStack(spacing: 5) {
            MenuBarUsageGlyph()
            Text(value)
                .monospacedDigit()
                .stxNumericValueTransition(value: value)
        }
        .accessibilityLabel("\(prefs.selectedProvider.shortName) Stats — \(prefs.menuBarPeriod.displayName)")
    }

    private func valueText(summary: UsageSummary, metric: MenuBarMetric) -> String {
        if env.store.sessions(for: env.preferences.selectedProvider).isEmpty && env.store.isLoading { return "…" }
        switch metric {
        case .tokens:
            return Format.tokens(summary.totalTokens(includingCacheRead: env.preferences.menuBarIncludesCache))
        case .cost:
            return Format.cost(summary.totalCost(for: env.preferences.costEstimationMode))
        }
    }
}

private struct MenuBarUsageGlyph: View {
    private let bars: [(height: CGFloat, opacity: Double)] = [
        (5, 0.62),
        (10, 0.9),
        (7, 0.74),
    ]

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(Array(bars.enumerated()), id: \.offset) { _, bar in
                Capsule(style: .continuous)
                    .fill(.primary.opacity(bar.opacity))
                    .frame(width: 2.5, height: bar.height)
            }
        }
        .padding(.bottom, 2)
        .overlay(alignment: .bottom) {
            Capsule(style: .continuous)
                .fill(.primary.opacity(0.5))
                .frame(width: 16, height: 1.5)
        }
        .frame(width: 18, height: 14, alignment: .center)
        .accessibilityHidden(true)
    }
}

#if DEBUG
// Standalone preview of the status-item content only. The label actually
// lives in the system menu bar via `MenuBarExtra` — a `Scene`, which Xcode's
// Canvas can't render. Run the app (`bash scripts/run-debug.sh`) to see it
// in the real menu bar.
#Preview("Menu bar label") {
    VStack(alignment: .leading, spacing: 14) {
        MenuBarLabel().environment(AppEnvironment.preview())
        MenuBarLabel().environment(AppEnvironment.preview())
            .environment(\.colorScheme, .dark)
            .padding(6)
            .background(.black)
        MenuBarLabel().environment(AppEnvironment.preview(populated: false))
    }
    .padding()
}
#endif
