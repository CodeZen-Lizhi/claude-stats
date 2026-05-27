import SwiftUI

struct AppBadge: View {
    enum Tone {
        case neutral
        case accent
        case muted
        case success
        case danger
    }

    let title: String
    let tone: Tone

    init(_ title: String, tone: Tone = .neutral) {
        self.title = title
        self.tone = tone
    }

    var body: some View {
        Text(title)
            .font(.sora(9, weight: .semibold).monospacedDigit())
            .foregroundStyle(foreground)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(background, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(stroke, lineWidth: 1)
            }
    }

    private var foreground: Color {
        switch tone {
        case .neutral: Color.primary.opacity(0.78)
        case .accent: Color.stxAccent
        case .muted: Color.stxMuted
        case .success: Color.green
        case .danger: Color.red
        }
    }

    private var background: Color {
        switch tone {
        case .neutral: Color.primary.opacity(0.045)
        case .accent: Color.stxAccent.opacity(0.10)
        case .muted: Color.primary.opacity(0.035)
        case .success: Color.green.opacity(0.10)
        case .danger: Color.red.opacity(0.10)
        }
    }

    private var stroke: Color {
        switch tone {
        case .neutral, .muted: Color.primary.opacity(0.055)
        case .accent: Color.stxAccent.opacity(0.18)
        case .success: Color.green.opacity(0.18)
        case .danger: Color.red.opacity(0.18)
        }
    }
}
