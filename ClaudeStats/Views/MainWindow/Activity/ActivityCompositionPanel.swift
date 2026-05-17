import SwiftUI

struct ActivityCompositionPanel: View {
    let title: String
    let caption: String
    let split: ActivityTimeSplit

    init(activity: DayActivity?) {
        self.title = "TIME SPLIT"
        self.caption = "Overlap, solo editor time, and AI activity outside the editor."
        self.split = ActivityTimeSplit(activity: activity)
    }

    init(trend: [DayActivity]) {
        self.title = "AGGREGATE SPLIT"
        self.caption = "Total time split across the selected range."
        self.split = ActivityTimeSplit(days: trend)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.sora(13, weight: .semibold))
                    .tracking(1.0)
                Spacer()
                Text(split.totalSeconds > 0 ? Format.duration(split.totalSeconds) : "--")
                    .font(.sora(12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.primary)
                    .help("Total split time")
            }

            Text(caption)
                .font(.sora(10))
                .foregroundStyle(Color.stxMuted)
                .fixedSize(horizontal: false, vertical: true)

            if split.totalSeconds <= 0 {
                Text("Nothing to break down for this selection.")
                    .font(.sora(12))
                    .foregroundStyle(Color.stxMuted)
                    .frame(maxWidth: .infinity, minHeight: 92, alignment: .center)
            } else {
                compositionBar
                rows
            }
        }
        .mainWindowPanel(padding: 16)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    private var compositionBar: some View {
        GeometryReader { proxy in
            HStack(spacing: 1) {
                ForEach(split.parts) { part in
                    let width = proxy.size.width * CGFloat(part.seconds / max(1, split.totalSeconds))
                    Rectangle()
                        .fill(part.color)
                        .frame(width: max(part.seconds > 0 ? CGFloat(2) : 0, width))
                }
                Spacer(minLength: 0)
            }
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 3, style: .continuous))
        }
        .frame(height: 8)
        .accessibilityLabel("Time split bar")
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(split.parts) { part in
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(part.color)
                        .frame(width: 9, height: 9)
                        .accessibilityHidden(true)
                    Text(part.label)
                        .font(.sora(11))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(Format.duration(part.seconds))
                        .font(.sora(11).monospacedDigit())
                        .foregroundStyle(Color.stxMuted)
                        .frame(minWidth: 72, alignment: .trailing)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(part.label), \(Format.duration(part.seconds))")
            }
        }
    }
}

struct ActivityTimeSplit: Equatable {
    struct Part: Identifiable, Equatable {
        let id: String
        let label: String
        let seconds: TimeInterval
        let color: Color

        static func == (lhs: Part, rhs: Part) -> Bool {
            lhs.id == rhs.id && lhs.label == rhs.label && lhs.seconds == rhs.seconds
        }
    }

    var overlapSeconds: TimeInterval
    var soloEditorSeconds: TimeInterval
    var aiOnlySeconds: TimeInterval

    var totalSeconds: TimeInterval {
        overlapSeconds + soloEditorSeconds + aiOnlySeconds
    }

    var parts: [Part] {
        [
            Part(id: "overlap", label: "AI-assisted coding", seconds: overlapSeconds, color: Color.stxAccent),
            Part(id: "solo-editor", label: "Solo editor time", seconds: soloEditorSeconds, color: Color.primary.opacity(0.26)),
            Part(id: "ai-only", label: "AI outside editor", seconds: aiOnlySeconds, color: Color.stxAccent.opacity(0.40)),
        ]
    }

    init(activity: DayActivity?) {
        overlapSeconds = activity?.overlapSeconds ?? 0
        soloEditorSeconds = activity?.soloIDESeconds ?? 0
        aiOnlySeconds = activity?.aiOnlySeconds ?? 0
    }

    init(days: [DayActivity]) {
        overlapSeconds = days.reduce(0) { $0 + $1.overlapSeconds }
        soloEditorSeconds = days.reduce(0) { $0 + $1.soloIDESeconds }
        aiOnlySeconds = days.reduce(0) { $0 + $1.aiOnlySeconds }
    }
}

#if DEBUG
#Preview {
    ActivityCompositionPanel(activity: nil)
        .padding(24)
        .frame(width: 360)
        .background(Color.stxBackground)
}
#endif
