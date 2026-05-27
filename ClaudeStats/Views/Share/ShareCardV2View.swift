import SwiftUI

struct ShareCardV2View: View {
    struct Config: Hashable {
        var selection: PeriodSelection
        var stampDate: Date
        var stampPrecision: ExportStampPrecision
    }

    @Environment(AppEnvironment.self) private var env
    let config: Config

    private var provider: ProviderKind { env.preferences.selectedProvider }
    private var summary: UsageSummary {
        env.store.summary(for: config.selection, provider: provider)
    }

    private var persona: SharePersona {
        SharePersona.choose(summary: summary)
    }

    private var badges: [ShareBadge] {
        ShareBadge.make(summary: summary).prefix(3).map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            hero
            proofGrid
            badgesRow
            footer
        }
        .padding(24)
        .background(
            LinearGradient(
                colors: persona.colors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .foregroundStyle(.white)
    }

    private var header: some View {
        HStack(alignment: .center) {
            Label(provider.shortName, systemImage: provider.iconSystemName)
                .font(.sora(12, weight: .semibold))
                .tracking(0.8)
            Spacer()
            Text(config.stampPrecision.string(for: config.stampDate))
                .font(.sora(10, weight: .medium))
                .foregroundStyle(.white.opacity(0.74))
        }
    }

    private var hero: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: persona.symbol)
                .font(.system(size: 36, weight: .semibold))
                .frame(width: 58, height: 58)
                .background(Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 5) {
                Text(persona.title)
                    .font(.sora(25, weight: .semibold))
                    .lineLimit(2)
                Text(config.selection.label())
                    .font(.sora(12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.74))
                    .lineLimit(1)
            }
        }
    }

    private var proofGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            proof("TOKENS", Format.tokens(summary.totalTokens(includingCacheRead: env.preferences.includeCacheInTokens)))
            proof("SESSIONS", "\(summary.sessionCount)")
            proof("REQUESTS", Format.tokens(summary.messageCount))
            proof("EST. COST", Format.cost(summary.totalCost(for: env.preferences.costEstimationMode)))
        }
    }

    private func proof(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.sora(9, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.66))
            Text(value)
                .font(.sora(19, weight: .semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var badgesRow: some View {
        HStack(spacing: 8) {
            ForEach(badges) { badge in
                Label(badge.title, systemImage: badge.symbol)
                    .font(.sora(10, weight: .semibold))
                    .lineLimit(1)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.13), in: Capsule())
            }
        }
    }

    private var footer: some View {
        HStack {
            Text("Codex Statistics")
                .font(.sora(10, weight: .semibold))
                .tracking(0.8)
            Spacer()
            Text("local-first stats")
                .font(.sora(10))
                .foregroundStyle(.white.opacity(0.66))
        }
    }
}

struct SharePersona: Equatable {
    let title: String
    let symbol: String
    let colors: [Color]

    static func choose(summary: UsageSummary) -> SharePersona {
        if summary.sessionCount >= 20 {
            return SharePersona(
                title: "Session Strategist",
                symbol: "rectangle.stack.fill",
                colors: [Color(red: 0.10, green: 0.22, blue: 0.30), Color(red: 0.08, green: 0.47, blue: 0.52)]
            )
        }
        if summary.totalTokens > 1_000_000 {
            return SharePersona(
                title: "Token Heavyweight",
                symbol: "bolt.fill",
                colors: [Color(red: 0.42, green: 0.12, blue: 0.26), Color(red: 0.84, green: 0.32, blue: 0.22)]
            )
        }
        if summary.models.count > 2 {
            return SharePersona(
                title: "Model Conductor",
                symbol: "slider.horizontal.3",
                colors: [Color(red: 0.18, green: 0.20, blue: 0.38), Color(red: 0.36, green: 0.33, blue: 0.62)]
            )
        }
        return SharePersona(
            title: "Focused Builder",
            symbol: "hammer.fill",
            colors: [Color(red: 0.13, green: 0.24, blue: 0.20), Color(red: 0.30, green: 0.52, blue: 0.34)]
        )
    }
}

struct ShareBadge: Identifiable, Equatable {
    let id: String
    let title: String
    let symbol: String

    static func make(summary: UsageSummary) -> [ShareBadge] {
        var badges: [ShareBadge] = []
        if summary.sessionCount >= 10 {
            badges.append(ShareBadge(id: "session-run", title: "Session Run", symbol: "text.bubble.fill"))
        }
        if summary.totalTokens > 500_000 {
            badges.append(ShareBadge(id: "deep-context", title: "Deep Context", symbol: "number.circle.fill"))
        }
        if summary.models.count > 1 {
            badges.append(ShareBadge(id: "model-mix", title: "Model Mix", symbol: "square.stack.3d.up.fill"))
        }
        if summary.totalCost > 5 {
            badges.append(ShareBadge(id: "serious-work", title: "Serious Work", symbol: "briefcase.fill"))
        }
        if badges.isEmpty {
            badges.append(ShareBadge(id: "clean-start", title: "Clean Start", symbol: "sparkles"))
        }
        return badges
    }
}

#if DEBUG
#Preview {
    ShareCardV2View(config: .init(selection: .preset(.last30Days), stampDate: .now, stampPrecision: .day))
        .environment(AppEnvironment.preview())
        .padding()
        .frame(width: 500)
}
#endif
