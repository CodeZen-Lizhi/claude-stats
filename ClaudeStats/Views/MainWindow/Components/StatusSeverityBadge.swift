import SwiftUI

struct StatusSeverityBadge: View {
    let label: String
    let indicatorTint: Color

    private static let backgroundColor = Color(
        red: 225.0 / 255.0,
        green: 225.0 / 255.0,
        blue: 227.0 / 255.0
    )

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(indicatorTint)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.sora(9, weight: .semibold))
                .foregroundStyle(Color.stxMuted)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Self.backgroundColor, in: Capsule())
    }
}
