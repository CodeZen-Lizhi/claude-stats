import SwiftUI

struct ActivityControls: View {
    @Binding var range: ActivityRange
    let selectedDay: Date
    let canStepForward: Bool
    let isLoading: Bool
    let onStepDay: (Int) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ActivityRangeChips(range: $range)

            if range == .day {
                dayStepper
                    .transition(.opacity)
            } else {
                Text("Last \(range.dayCount) days")
                    .font(.sora(11, weight: .medium))
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .help("Loading activity")
            }
        }
        .animation(.easeOut(duration: 0.18), value: range)
    }

    private var dayStepper: some View {
        HStack(spacing: 4) {
            stepButton(systemName: "chevron.left", help: "Previous day") {
                onStepDay(-1)
            }

            Text(Format.day(selectedDay))
                .font(.sora(11, weight: .medium).monospacedDigit())
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(minWidth: 52)
                .accessibilityLabel("Selected day")

            stepButton(systemName: "chevron.right", disabled: !canStepForward, help: "Next day") {
                onStepDay(1)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Day navigation")
    }

    private func stepButton(
        systemName: String,
        disabled: Bool = false,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(disabled ? Color.stxMuted.opacity(0.35) : Color.stxMuted)
                .frame(width: 24, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help(help)
        .accessibilityLabel(help)
    }
}

private struct ActivityRangeChips: View {
    @Binding var range: ActivityRange

    var body: some View {
        HStack(spacing: 4) {
            ForEach(ActivityRange.allCases) { value in
                chip(value)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Activity range")
    }

    private func chip(_ value: ActivityRange) -> some View {
        let selected = range == value
        return Button {
            withAnimation(.easeOut(duration: 0.18)) {
                range = value
            }
        } label: {
            Text(value.mainWindowLabel)
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
        .help(value == .day ? "Show one day" : "Show last \(value.dayCount) days")
        .accessibilityLabel(value == .day ? "Day" : "Last \(value.dayCount) days")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

#if DEBUG
#Preview {
    struct Wrap: View {
        @State private var range = ActivityRange.day
        var body: some View {
            ActivityControls(
                range: $range,
                selectedDay: .now,
                canStepForward: false,
                isLoading: false,
                onStepDay: { _ in }
            )
            .padding(24)
            .frame(width: 720)
            .background(Color.stxBackground)
        }
    }

    return Wrap()
}
#endif
