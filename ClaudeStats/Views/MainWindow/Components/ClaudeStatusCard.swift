import SwiftUI

struct ClaudeStatusCard: View {
    let status: ClaudeStatusViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.stxPanel, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.stxStroke, lineWidth: 1))
        .task { await status.refreshIfNeeded() }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Text("CLAUDE STATUS")
                .font(.sora(9, weight: .medium))
                .tracking(0.4)
                .foregroundStyle(Color.stxMuted)
            if let snapshot = status.snapshot {
                severityBadge(snapshot.rollup.severity, label: snapshot.rollup.description)
            } else if status.isLoading {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text("Checking")
                        .font(.sora(10, weight: .medium))
                        .foregroundStyle(Color.stxMuted)
                }
            }
            Spacer()
            Text(updatedLabel)
                .font(.sora(10))
                .foregroundStyle(Color.stxMuted)
                .lineLimit(1)
            Button {
                Task { await status.refresh(force: true) }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.stxMuted)
            .help("Refresh Claude Status")
            Link(destination: status.statusPageURL) {
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.stxMuted)
            .help("Open Claude Status")
        }
    }

    @ViewBuilder
    private var content: some View {
        if let snapshot = status.snapshot {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(status.visibleComponents) { component in
                    componentRow(component)
                }
                if let incident = snapshot.activeIncident {
                    incidentRow(incident)
                } else if status.isStale, let lastError = status.lastError {
                    cachedStatusRow(lastError)
                }
            }
        } else if let lastError = status.lastError {
            Text(lastError)
                .font(.sora(11))
                .foregroundStyle(Color.stxMuted)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text("Checking Claude Status…")
                .font(.sora(11))
                .foregroundStyle(Color.stxMuted)
        }
    }

    private var updatedLabel: String {
        guard let snapshot = status.snapshot else { return "" }
        let date = snapshot.pageUpdatedAt ?? snapshot.fetchedAt
        let stale = status.isStale ? " · stale" : ""
        return "UPD \(Format.relativeDate(date))\(stale)"
    }

    private func severityBadge(_ severity: ClaudeStatusSeverity, label: String) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(severity.tint)
                .frame(width: 6, height: 6)
            Text(label.uppercased())
                .font(.sora(9, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(severity.tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(severity.tint.opacity(0.12), in: Capsule())
        .overlay(Capsule().strokeBorder(severity.tint.opacity(0.35), lineWidth: 1))
    }

    private func componentRow(_ component: ClaudeStatusComponent) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: component.status.symbolName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(component.status.tint)
                .frame(width: 16)
            Text(component.name)
                .font(.sora(12, weight: .medium))
                .lineLimit(1)
            Spacer(minLength: 12)
            Text(component.status.displayName)
                .font(.sora(11))
                .foregroundStyle(component.status.tint)
                .lineLimit(1)
        }
    }

    private func incidentRow(_ incident: ClaudeStatusIncident) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(incident.impact.tint)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(incident.name)
                    .font(.sora(11, weight: .medium))
                    .lineLimit(2)
                if let shortlink = incident.shortlink {
                    Link("View incident", destination: shortlink)
                        .font(.sora(10))
                }
            }
        }
        .padding(.top, 2)
    }

    private func cachedStatusRow(_ lastError: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.stxMuted)
                .frame(width: 16)
            Text("Using cached status. \(lastError)")
                .font(.sora(11))
                .foregroundStyle(Color.stxMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 2)
    }
}

private extension ClaudeStatusSeverity {
    var tint: Color {
        switch self {
        case .operational: Color.green
        case .underMaintenance: Color.blue
        case .degradedPerformance: Color.orange
        case .partialOutage, .majorOutage: Color.red
        case .unknown: Color.stxMuted
        }
    }

    var symbolName: String {
        switch self {
        case .operational: "checkmark.circle.fill"
        case .underMaintenance: "wrench.and.screwdriver.fill"
        case .degradedPerformance: "exclamationmark.circle.fill"
        case .partialOutage, .majorOutage: "xmark.octagon.fill"
        case .unknown: "questionmark.circle.fill"
        }
    }
}

#if DEBUG
#Preview("Claude Status Card") {
    let env = AppEnvironment.preview()
    return ClaudeStatusCard(status: env.claudeStatus)
        .padding()
        .frame(width: 720)
        .background(Color.stxBackground)
}
#endif
