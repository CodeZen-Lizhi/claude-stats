import SwiftUI

struct FeaturesSettingsView: View {
    @Environment(AppEnvironment.self) private var env

    var onSelectSection: (SettingsSection) -> Void = { _ in }

    private let columns = [
        GridItem(.adaptive(minimum: 340), spacing: 16, alignment: .top)
    ]

    var body: some View {
        @Bindable var prefs = env.preferences

        LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
            gitTrackingCard(prefs: prefs)
            systemMonitorCard(prefs: prefs)
            githubCard(prefs: prefs)
            floatingTabCard(prefs: prefs)
            notchIslandCard(prefs: prefs)
        }
    }

    private func gitTrackingCard(prefs: Preferences) -> some View {
        @Bindable var prefs = prefs
        return FeatureControlCard(
            title: "Git Tracking",
            symbol: "arrow.triangle.branch",
            description: "Reads local commit history for repos used with Claude and correlates code churn with sessions.",
            status: prefs.gitTrackingEnabled ? gitTrackingStatus(prefs: prefs) : "Hidden from Tools",
            isOn: $prefs.gitTrackingEnabled,
            onConfigure: { onSelectSection(.tracking) }
        ) {
            GitTrackingFeaturePreview()
        }
    }

    private func systemMonitorCard(prefs: Preferences) -> some View {
        @Bindable var prefs = prefs
        return FeatureControlCard(
            title: "System Monitor",
            symbol: "cpu",
            description: "Shows read-only CPU, memory, disk, network, battery, GPU, and thermal sampling on demand.",
            status: prefs.systemMonitorEnabled ? systemMonitorStatus(prefs: prefs) : "Hidden from Stats",
            isOn: $prefs.systemMonitorEnabled,
            onConfigure: { onSelectSection(.systemMonitor) }
        ) {
            SystemMonitorFeaturePreview()
        }
    }

    private func githubCard(prefs: Preferences) -> some View {
        @Bindable var prefs = prefs
        return FeatureControlCard(
            title: "GitHub Comparison",
            symbol: "chevron.left.forwardslash.chevron.right",
            description: "Adds a GitHub heatmap and local-vs-GitHub overlap view to the Dashboard.",
            status: prefs.githubEnabled ? githubStatus : "Dashboard comparison off",
            isOn: $prefs.githubEnabled,
            onConfigure: { onSelectSection(.github) }
        ) {
            GitHubFeaturePreview()
        }
    }

    private func floatingTabCard(prefs: Preferences) -> some View {
        @Bindable var prefs = prefs
        return FeatureControlCard(
            title: "Floating Edge Tab",
            symbol: "rectangle.on.rectangle",
            description: "Keeps Claude Stats reachable from a small screen-edge tab when the menu bar is crowded.",
            status: prefs.floatingTabEnabled ? "Docked on \(prefs.floatingTabEdge.rawValue.capitalized)" : "Off",
            isOn: $prefs.floatingTabEnabled,
            onConfigure: { onSelectSection(.menuBar) }
        ) {
            FloatingTabFeaturePreview()
        }
    }

    private func notchIslandCard(prefs: Preferences) -> some View {
        @Bindable var prefs = prefs
        return FeatureControlCard(
            title: "Notch Island",
            symbol: "capsule.portrait.tophalf.filled",
            description: "Adds an Atoll-backed Dynamic Island surface around the camera notch while keeping existing app entry points.",
            status: prefs.notchIslandEnabled ? notchIslandStatus(prefs: prefs) : "Off",
            isOn: $prefs.notchIslandEnabled,
            onConfigure: { onSelectSection(.notchIsland) }
        ) {
            NotchIslandFeaturePreview()
        }
    }

    private func gitTrackingStatus(prefs: Preferences) -> String {
        prefs.gitOpensInWindow ? "Separate window" : "Panel tab"
    }

    private func systemMonitorStatus(prefs: Preferences) -> String {
        let count = prefs.systemMonitorVisibleModules.count
        return "\(prefs.systemMonitorRefreshRate.displayName) - \(count) modules"
    }

    private func notchIslandStatus(prefs: Preferences) -> String {
        "\(prefs.notchIslandSizePreset.displayName) - \(prefs.notchIslandEnabledModules.count) modules"
    }

    private var githubStatus: String {
        switch env.github.status {
        case .disconnected:
            return "Not connected"
        case .connecting:
            return "Connecting"
        case .connected(let login, _, _):
            return "@\(login)"
        case .failed:
            return "Needs attention"
        }
    }

}

private struct GitTrackingFeaturePreview: View {
    private let rows = [
        ("aurora", "9 commits", 0.92),
        ("ledger", "4 commits", 0.54),
        ("design-system", "3 commits", 0.38),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Repository activity", systemImage: "folder")
                    .font(.sora(12, weight: .semibold))
                Spacer()
                Text("+1.8k")
                    .font(.sora(10, weight: .medium).monospacedDigit())
                    .foregroundStyle(Color.stxMuted)
            }

            ForEach(rows, id: \.0) { row in
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(row.0)
                            .font(.sora(11, weight: .medium))
                        Spacer()
                        Text(row.1)
                            .font(.sora(10))
                            .foregroundStyle(Color.stxMuted)
                    }
                    GeometryReader { proxy in
                        Capsule()
                            .fill(Color.primary.opacity(0.08))
                            .overlay(alignment: .leading) {
                                Capsule()
                                    .fill(Color.stxAccent.opacity(0.72))
                                    .frame(width: proxy.size.width * row.2)
                            }
                    }
                    .frame(height: 7)
                }
            }
        }
    }
}

private struct SystemMonitorFeaturePreview: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("System", systemImage: "cpu")
                    .font(.sora(12, weight: .semibold))
                Spacer()
                Text("3s")
                    .font(.sora(10, weight: .medium).monospacedDigit())
                    .foregroundStyle(Color.stxMuted)
            }

            HStack(spacing: 8) {
                SystemPreviewTile(title: "CPU", value: "42%", colors: [Color.stxRamp[1], Color.stxRamp[0]])
                SystemPreviewTile(title: "Memory", value: "64%", colors: [Color.stxRamp[0], Color.stxRamp[3]])
                SystemPreviewTile(title: "Net", value: "1.8M", colors: [Color.stxRamp[3], Color.stxRamp[0]])
            }
        }
    }
}

private struct GitHubFeaturePreview: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Overlap", systemImage: "square.grid.3x3")
                    .font(.sora(12, weight: .semibold))
                Spacer()
                Text("90d")
                    .font(.sora(10, weight: .medium).monospacedDigit())
                    .foregroundStyle(Color.stxMuted)
            }

            PreviewHeatmap(colors: colors)

            HStack(spacing: 8) {
                legend("Both", Color.stxAccent)
                legend("Local", Color.primary.opacity(0.44))
                legend("GitHub", Color.green.opacity(0.72))
            }
        }
    }

    private func legend(_ text: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text)
                .font(.sora(9))
                .foregroundStyle(Color.stxMuted)
        }
    }

    private var colors: [Color] {
        (0..<70).map { index in
            switch index % 9 {
            case 0, 4: Color.stxAccent
            case 2, 7: Color.green.opacity(0.72)
            case 5: Color.primary.opacity(0.44)
            default: Color.primary.opacity(0.08)
            }
        }
    }
}

private struct FloatingTabFeaturePreview: View {
    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.045))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.stxStroke, lineWidth: 1)
                }
                .overlay(alignment: .trailing) {
                    VStack(spacing: 0) {
                        Text("claude")
                            .font(.sora(11, weight: .semibold))
                            .tracking(0.8)
                            .rotationEffect(.degrees(-90))
                            .frame(width: 76, height: 24)
                    }
                    .frame(width: 28, height: 88)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.stxStroke, lineWidth: 1))
                    .padding(.trailing, -7)
                }

            VStack(alignment: .leading, spacing: 8) {
                PreviewMetric(title: "Tokens", value: "119M")
                PreviewMetric(title: "Cost", value: "$42")
            }
            .frame(width: 92)
        }
    }
}

private struct NotchIslandFeaturePreview: View {
    var body: some View {
        VStack(spacing: 12) {
            UnevenRoundedRectangle(
                topLeadingRadius: 6,
                bottomLeadingRadius: 14,
                bottomTrailingRadius: 14,
                topTrailingRadius: 6,
                style: .continuous
            )
            .fill(Color.black)
            .frame(width: 188, height: 34)
            .shadow(color: .black.opacity(0.18), radius: 8, y: 3)

            HStack(spacing: 24) {
                ForEach(["house.fill", "tray.fill", "timer", "chart.xyaxis.line"], id: \.self) { symbol in
                    Image(systemName: symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(symbol == "house.fill" ? Color.primary : Color.stxMuted)
                        .frame(width: 26, height: 26)
                        .background {
                            if symbol == "house.fill" {
                                Capsule()
                                    .fill(Color.primary.opacity(0.12))
                            }
                        }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct PreviewMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(.sora(8, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(Color.stxMuted)
            Text(value)
                .font(.sora(15, weight: .semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

private struct PreviewLane: View {
    let label: String
    let color: Color
    let widths: [CGFloat]

    var body: some View {
        HStack(spacing: 7) {
            Text(label)
                .font(.sora(9, weight: .medium))
                .foregroundStyle(Color.stxMuted)
                .frame(width: 24, alignment: .leading)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.06))
                    HStack(spacing: 4) {
                        ForEach(Array(widths.enumerated()), id: \.offset) { index, width in
                            Capsule()
                                .fill(color.opacity(index == 1 ? 0.82 : 0.56))
                                .frame(width: proxy.size.width * width)
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }
            .frame(height: 9)
        }
    }
}

private struct SystemPreviewTile: View {
    let title: String
    let value: String
    let colors: [Color]

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title.uppercased())
                .font(.sora(8, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(Color.stxMuted)
            Text(value)
                .font(.sora(15, weight: .semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            SystemTimelineChart(
                bars: (0..<18).map { index in
                    colors.enumerated().map { offset, color in
                        let base = 0.08 + Double((index + offset * 2) % 7) * 0.018
                        return SystemTimelineSegment(value: base, color: color)
                    }
                },
                placeholderCount: 18
            )
            .frame(height: 42)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

private struct PreviewHeatmap: View {
    let colors: [Color]

    var body: some View {
        Grid(horizontalSpacing: 4, verticalSpacing: 4) {
            ForEach(0..<7, id: \.self) { row in
                GridRow {
                    ForEach(0..<10, id: \.self) { column in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(colors[(column * 7 + row) % colors.count])
                            .frame(width: 12, height: 12)
                    }
                }
            }
        }
    }
}

#if DEBUG
#Preview {
    FeaturesSettingsView()
        .environment(AppEnvironment.preview())
        .padding()
        .frame(width: 900)
        .background(Color.stxBackground)
}
#endif
