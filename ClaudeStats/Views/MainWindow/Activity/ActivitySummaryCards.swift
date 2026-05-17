import SwiftUI

struct ActivitySummaryMetrics: Equatable {
    var editorSeconds: TimeInterval
    var aiSeconds: TimeInterval
    var overlapSeconds: TimeInterval
    var assistedRatio: Double?

    static func day(_ activity: DayActivity?) -> ActivitySummaryMetrics {
        ActivitySummaryMetrics(
            editorSeconds: activity?.ideSeconds ?? 0,
            aiSeconds: activity?.aiSeconds ?? 0,
            overlapSeconds: activity?.overlapSeconds ?? 0,
            assistedRatio: activity.map(\.assistedRatio)
        )
    }

    static func trend(_ days: [DayActivity]) -> ActivitySummaryMetrics {
        let editor = days.reduce(0) { $0 + $1.ideSeconds }
        let ai = days.reduce(0) { $0 + $1.aiSeconds }
        let overlap = days.reduce(0) { $0 + $1.overlapSeconds }
        let ratio = editor > 0 ? overlap / editor : nil

        return ActivitySummaryMetrics(
            editorSeconds: editor,
            aiSeconds: ai,
            overlapSeconds: overlap,
            assistedRatio: ratio
        )
    }
}

struct ActivitySummaryCards: View {
    let metrics: ActivitySummaryMetrics
    let assistedLabel: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    card("Editor time", Format.duration(metrics.editorSeconds))
                    card("AI active", Format.duration(metrics.aiSeconds))
                    card("Overlap", Format.duration(metrics.overlapSeconds))
                    card(assistedLabel, metrics.assistedRatio.map(Format.percent) ?? "--")
                }
            }

            Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    card("Editor time", Format.duration(metrics.editorSeconds))
                    card("AI active", Format.duration(metrics.aiSeconds))
                }
                GridRow {
                    card("Overlap", Format.duration(metrics.overlapSeconds))
                    card(assistedLabel, metrics.assistedRatio.map(Format.percent) ?? "--")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Activity summary")
    }

    private func card(_ label: String, _ value: String) -> some View {
        StatCard(label: label, value: value)
    }
}

#if DEBUG
#Preview {
    ActivitySummaryCards(
        metrics: ActivitySummaryMetrics(
            editorSeconds: 4_200,
            aiSeconds: 2_700,
            overlapSeconds: 1_860,
            assistedRatio: 0.44
        ),
        assistedLabel: "AI-assisted"
    )
    .padding(24)
    .frame(width: 780)
    .background(Color.stxBackground)
}
#endif
