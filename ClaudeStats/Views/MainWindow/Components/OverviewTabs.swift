import SwiftUI

/// Segmented "Overview | Models" pill used at the top of the Dashboard.
/// Selection is animated via a single matched-geometry capsule slid under the
/// active tab.
struct OverviewTabs: View {
    @Binding var section: DashboardViewModel.Section
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 2) {
            tab(.overview, label: "Overview")
            tab(.models, label: "Models")
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
    }

    @ViewBuilder
    private func tab(_ value: DashboardViewModel.Section, label: String) -> some View {
        let isSelected = section == value
        Button {
            withAnimation(.easeOut(duration: 0.18)) { section = value }
        } label: {
            Text(label)
                .font(.sora(12, weight: .medium))
                .foregroundStyle(isSelected ? .primary : Color.stxMuted)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.stxPanel)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(Color.stxStroke, lineWidth: 1)
                            )
                            .matchedGeometryEffect(id: "tab-pill", in: ns)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#if DEBUG
#Preview {
    struct Wrap: View {
        @State var sec: DashboardViewModel.Section = .overview
        var body: some View {
            OverviewTabs(section: $sec).padding(24).frame(width: 360)
        }
    }
    return Wrap().background(Color.stxBackground)
}
#endif
