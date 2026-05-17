import SwiftUI

struct SystemMetricLegend: Identifiable {
    let id: String
    var label: String
    var value: String
    var color: Color

    init(_ label: String, value: String, color: Color) {
        self.id = label
        self.label = label
        self.value = value
        self.color = color
    }
}

struct SystemMetricCard<Content: View>: View {
    let title: String
    let symbol: String
    let value: String
    var caption: String
    var legends: [SystemMetricLegend]
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.stxMuted)
                    .frame(width: 18)
                Text(title.uppercased())
                    .font(.sora(13, weight: .semibold))
                    .tracking(0.8)
                Spacer(minLength: 8)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.sora(28, weight: .semibold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text(caption)
                    .font(.sora(11))
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !legends.isEmpty {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 92), spacing: 8)],
                    alignment: .leading,
                    spacing: 7
                ) {
                    ForEach(legends) { legend in
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(legend.color)
                                .frame(width: 8, height: 8)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(legend.label)
                                    .font(.sora(9))
                                    .foregroundStyle(Color.stxMuted)
                                    .lineLimit(1)
                                Text(legend.value)
                                    .font(.sora(10, weight: .medium).monospacedDigit())
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }

            StxRule()
            content()
        }
        .mainWindowPanel(padding: 16)
    }
}
