import SwiftUI

struct UsageLimitPanel: View {
    let provider: ProviderKind
    let report: UsageLimitReport?
    let isLoading: Bool
    let actionMessage: String?
    let onRefresh: () -> Void
    let onInstallClaudeBridge: (() -> Void)?
    let onCopyClaudeSettingsSnippet: (() -> Void)?
    let onOpenClaudeSettings: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            content
        }
        .mainUsagePanel(padding: 16)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(provider.shortName) usage limits")
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Text("USAGE LIMITS")
                .font(.sora(13, weight: .semibold))
                .tracking(1.0)
            statusBadge
            Spacer(minLength: 12)
            if let label = updatedLabel {
                Text(label)
                    .font(.sora(10))
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(1)
            }
            if isLoading {
                ProgressView()
                    .controlSize(.mini)
            }
            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.stxMuted)
            .help("Refresh usage limits")
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        let status = report?.status ?? (isLoading ? .waitingForNextResponse : .unsupported)
        HStack(spacing: 5) {
            Circle()
                .fill(tint(for: status))
                .frame(width: 6, height: 6)
            Text(label(for: status).uppercased())
                .font(.sora(9, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(tint(for: status))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(tint(for: status).opacity(0.12), in: Capsule())
        .overlay(Capsule().strokeBorder(tint(for: status).opacity(0.35), lineWidth: 1))
    }

    @ViewBuilder
    private var content: some View {
        if let report {
            switch report.status {
            case .fresh:
                if let snapshot = report.snapshot {
                    limitWindows(snapshot.windows)
                    sourceFooter(snapshot: snapshot)
                }
            case .setupRequired where provider == .claude:
                setupRequiredContent(message: report.message)
            case .waitingForNextResponse:
                stateContent(
                    systemImage: "clock.arrow.circlepath",
                    title: "Waiting for the next \(provider.shortName) response",
                    message: report.message,
                    lastCapturedAt: report.lastCapturedAt
                )
            case .unavailable:
                stateContent(
                    systemImage: "exclamationmark.triangle.fill",
                    title: "Usage limits unavailable",
                    message: report.message,
                    lastCapturedAt: report.lastCapturedAt
                )
            case .setupRequired:
                stateContent(
                    systemImage: "wrench.and.screwdriver.fill",
                    title: "Setup required",
                    message: report.message,
                    lastCapturedAt: report.lastCapturedAt
                )
            case .unsupported:
                EmptyView()
            }
        } else {
            stateContent(
                systemImage: "clock.arrow.circlepath",
                title: isLoading ? "Checking usage limits" : "Usage limits not loaded",
                message: nil,
                lastCapturedAt: nil
            )
        }
        if let actionMessage {
            StxRule()
            Text(actionMessage)
                .font(.sora(11))
                .foregroundStyle(Color.stxMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func limitWindows(_ windows: [UsageLimitWindow]) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                ForEach(windows) { window in
                    UsageLimitWindowCard(window: window)
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                ForEach(windows) { window in
                    UsageLimitWindowCard(window: window)
                }
            }
        }
    }

    private func setupRequiredContent(message: String?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            stateContent(
                systemImage: "terminal.fill",
                title: "Connect Claude Code status line",
                message: message,
                lastCapturedAt: nil
            )
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    claudeSetupButtons
                    Spacer(minLength: 0)
                }
                VStack(alignment: .leading, spacing: 8) {
                    claudeSetupButtons
                }
            }
        }
    }

    @ViewBuilder
    private var claudeSetupButtons: some View {
        if let onInstallClaudeBridge {
            Button("Install bridge", action: onInstallClaudeBridge)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        if let onCopyClaudeSettingsSnippet {
            Button("Copy settings snippet", action: onCopyClaudeSettingsSnippet)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        if let onOpenClaudeSettings {
            Button("Open Claude settings", action: onOpenClaudeSettings)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }

    private func stateContent(systemImage: String, title: String, message: String?, lastCapturedAt: Date?) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.stxMuted)
                .frame(width: 18)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.sora(12, weight: .semibold))
                    .foregroundStyle(.primary)
                if let message {
                    Text(message)
                        .font(.sora(11))
                        .foregroundStyle(Color.stxMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let lastCapturedAt {
                    Text("Last snapshot \(Format.relativeDate(lastCapturedAt))")
                        .font(.sora(10))
                        .foregroundStyle(Color.stxMuted)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func sourceFooter(snapshot: UsageLimitSnapshot) -> some View {
        HStack(spacing: 8) {
            Text(snapshot.sourceLabel)
                .font(.sora(10))
                .foregroundStyle(Color.stxMuted)
                .lineLimit(1)
            if let planType = snapshot.planType {
                Text(planType.uppercased())
                    .font(.sora(9, weight: .semibold))
                    .foregroundStyle(Color.stxMuted)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.06), in: Capsule())
            }
            Spacer(minLength: 0)
        }
    }

    private var updatedLabel: String? {
        guard let capturedAt = report?.lastCapturedAt else { return nil }
        return "Updated \(Format.relativeDate(capturedAt))"
    }

    private func label(for status: UsageLimitStatus) -> String {
        switch status {
        case .fresh:
            "Fresh"
        case .setupRequired:
            "Setup"
        case .waitingForNextResponse:
            "Waiting"
        case .unavailable:
            "Unavailable"
        case .unsupported:
            "Unsupported"
        }
    }

    private func tint(for status: UsageLimitStatus) -> Color {
        switch status {
        case .fresh:
            Color.green
        case .setupRequired:
            Color.blue
        case .waitingForNextResponse:
            Color.orange
        case .unavailable:
            Color.red
        case .unsupported:
            Color.stxMuted
        }
    }
}

private struct UsageLimitWindowCard: View {
    let window: UsageLimitWindow

    private var tint: Color {
        switch window.remainingPercent {
        case let remaining where remaining > 50:
            Color.green
        case 20...50:
            Color.orange
        default:
            Color.red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text(window.label.uppercased())
                    .font(.sora(10, weight: .semibold))
                    .foregroundStyle(Color.stxMuted)
                Spacer(minLength: 8)
                Text(resetLabel)
                    .font(.sora(10))
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(1)
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Format.percentPoints(window.remainingPercent))
                    .font(.sora(24, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .stxNumericValueTransition(value: Format.percentPoints(window.remainingPercent))
                Text("left")
                    .font(.sora(11, weight: .medium))
                    .foregroundStyle(Color.stxMuted)
                Spacer(minLength: 8)
                Text("\(Format.percentPoints(window.clampedUsedPercent)) used")
                    .font(.sora(10))
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(1)
            }

            UsageLimitSegmentStrip(
                usedPercent: window.clampedUsedPercent,
                remainingTint: tint
            )

            HStack(spacing: 10) {
                UsageLimitSegmentLegendItem(label: "Left", tint: tint, style: .solid)
                UsageLimitSegmentLegendItem(label: "Used", tint: Color.primary.opacity(0.34), style: .hatched)
                Spacer(minLength: 0)
            }
        }
        .padding(.vertical, 4)
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(window.label) usage limit")
        .accessibilityValue("\(Format.percentPoints(window.remainingPercent)) remaining, \(Format.percentPoints(window.clampedUsedPercent)) used, \(resetLabel)")
    }

    private var resetLabel: String {
        guard let resetAt = window.resetAt else { return "Reset unknown" }
        return "Resets \(Format.relativeDate(resetAt))"
    }
}

private struct UsageLimitSegmentStrip: View {
    let usedPercent: Double
    let remainingTint: Color

    private let segmentCount = 28
    private let segmentHeight: CGFloat = 34

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<segmentCount, id: \.self) { index in
                if index < remainingSegmentCount {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(remainingTint)
                        .frame(maxWidth: .infinity)
                        .frame(height: segmentHeight)
                } else {
                    UsageLimitHatchedSegment()
                        .frame(maxWidth: .infinity)
                        .frame(height: segmentHeight)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: segmentHeight)
        .accessibilityHidden(true)
    }

    private var usedSegmentCount: Int {
        let clamped = min(100, max(0, usedPercent))
        guard clamped > 0 else { return 0 }
        return min(segmentCount, max(1, Int((clamped / 100 * Double(segmentCount)).rounded(.up))))
    }

    private var remainingSegmentCount: Int {
        segmentCount - usedSegmentCount
    }
}

private struct UsageLimitSegmentLegendItem: View {
    enum Style {
        case solid
        case hatched
    }

    let label: String
    let tint: Color
    let style: Style

    var body: some View {
        HStack(spacing: 5) {
            Group {
                switch style {
                case .solid:
                    Rectangle()
                        .fill(tint)
                case .hatched:
                    UsageLimitHatchedSegment()
                }
            }
            .frame(width: 8, height: 8)
            Text(label)
                .font(.sora(9))
                .foregroundStyle(Color.stxMuted)
        }
        .accessibilityHidden(true)
    }
}

private struct UsageLimitHatchedSegment: View {
    private let baseTint = Color.primary.opacity(0.12)
    private let stripeTint = Color.primary.opacity(0.34)

    var body: some View {
        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
            .fill(baseTint)
            .overlay {
                DiagonalStripeShape(spacing: 6)
                    .stroke(stripeTint, style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
                    .clipShape(RoundedRectangle(cornerRadius: 1.5, style: .continuous))
            }
    }
}

private struct DiagonalStripeShape: Shape {
    let spacing: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let stride = max(2, spacing)
        var startX = rect.minX - rect.height

        while startX < rect.maxX {
            path.move(to: CGPoint(x: startX, y: rect.maxY))
            path.addLine(to: CGPoint(x: startX + rect.height, y: rect.minY))
            startX += stride
        }

        return path
    }
}

#if DEBUG
#Preview {
    UsageLimitPanel(
        provider: .codex,
        report: .fresh(
            provider: .codex,
            snapshot: UsageLimitSnapshot(
                provider: .codex,
                windows: [
                    UsageLimitWindow(id: "primary", label: "5h", usedPercent: 38, resetAt: Date().addingTimeInterval(2_400), windowMinutes: 300),
                    UsageLimitWindow(id: "secondary", label: "7d", usedPercent: 12, resetAt: Date().addingTimeInterval(400_000), windowMinutes: 10_080),
                ],
                capturedAt: Date().addingTimeInterval(-120),
                sourceLabel: "Codex rollout",
                sourcePath: nil,
                planType: "pro",
                limitID: "codex"
            )
        ),
        isLoading: false,
        actionMessage: nil,
        onRefresh: {},
        onInstallClaudeBridge: nil,
        onCopyClaudeSettingsSnippet: nil,
        onOpenClaudeSettings: nil
    )
    .padding(24)
    .frame(width: 760)
    .background(Color.stxBackground)
}
#endif
