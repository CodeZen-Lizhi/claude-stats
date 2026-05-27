import SwiftUI

struct GitChangedFileRow: View {
    static let rowHeight: CGFloat = 30
    static let contentHorizontalInset: CGFloat = 12

    private static let metricSpacing: CGFloat = 16

    let model: GitChangedFileRowModel
    let onOpen: (GitChangedFileRowModel) -> Void

    @ViewBuilder
    var body: some View {
        if model.isOpenable {
            Button {
                onOpen(model)
            } label: {
                rowChrome
            }
            .buttonStyle(.plain)
            .rowFrame
            .help(model.helpText)
            .accessibilityLabel(Text(model.accessibilityLabel))
        } else {
            rowChrome
                .rowFrame
                .help(model.helpText)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text(model.accessibilityLabel))
        }
    }

    private var rowChrome: some View {
        HStack(spacing: Self.metricSpacing) {
            leadingMetric
                .fixedSize(horizontal: true, vertical: false)
            Text(model.path)
                .font(.sora(10, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .layoutPriority(1)

            Spacer(minLength: 8)

            if !model.statusBadges.isEmpty {
                statusBadges
            }

            if model.isOpenable {
                disclosureIcon
            }
        }
        .padding(.horizontal, Self.contentHorizontalInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var leadingMetric: some View {
        if let badge = model.kindBadge {
            badgeView(badge)
        } else if let churn = model.churn {
            churnView(churn)
        }
    }

    @ViewBuilder
    private func churnView(_ churn: GitChangedFileRowModel.Churn) -> some View {
        switch churn {
        case .binary:
            Text(L10n.string("git.changed_files.binary", defaultValue: "bin"))
                .font(.sora(10).monospacedDigit())
                .foregroundStyle(Color.stxMuted)
        case .text(let insertions, let deletions):
            HStack(spacing: Self.metricSpacing) {
                Text("+\(insertions)")
                    .font(.sora(10).monospacedDigit())
                    .foregroundStyle(GitPalette.add)
                Text("-\(deletions)")
                    .font(.sora(10).monospacedDigit())
                    .foregroundStyle(GitPalette.del)
            }
        }
    }

    private var statusBadges: some View {
        HStack(spacing: 5) {
            ForEach(model.statusBadges) { badge in
                badgeView(badge)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func badgeView(_ badge: GitChangedFileRowModel.Badge) -> some View {
        AppBadge(badge.label, tone: appBadgeTone(badge.tone))
            .help(badge.help)
    }

    private var disclosureIcon: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(Color.stxMuted)
            .frame(width: 22, height: 22)
    }

    private func appBadgeTone(_ tone: GitChangedFileRowModel.Tone) -> AppBadge.Tone {
        switch tone {
        case .add: return .success
        case .delete: return .danger
        case .tag, .head: return .accent
        case .danger: return .danger
        case .muted: return .muted
        }
    }
}

private extension View {
    var rowFrame: some View {
        frame(
            maxWidth: .infinity,
            minHeight: GitChangedFileRow.rowHeight,
            maxHeight: GitChangedFileRow.rowHeight,
            alignment: .leading
        )
        .contentShape(Rectangle())
    }
}
