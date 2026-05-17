import SwiftUI

struct TerminalBackdropView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let style: TerminalBackgroundStyle
    var colorScheme: ColorScheme = .light
    @State private var animated = false

    private var isDark: Bool {
        colorScheme == .dark
    }

    var body: some View {
        ZStack {
            baseColor

            switch style {
            case .fluidGradient:
                fluidGradient
            case .solid:
                baseColor
            }
        }
        .onAppear {
            guard style == .fluidGradient, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 16).repeatForever(autoreverses: true)) {
                animated = true
            }
        }
        .onChange(of: style) { _, newStyle in
            guard newStyle == .fluidGradient, !reduceMotion else {
                animated = false
                return
            }
            withAnimation(.easeInOut(duration: 16).repeatForever(autoreverses: true)) {
                animated = true
            }
        }
        .clipped()
    }

    private var baseColor: Color {
        isDark
            ? Color(red: 0.018, green: 0.021, blue: 0.026)
            : Color(red: 0.050, green: 0.054, blue: 0.060)
    }

    private var mutedOrange: Color {
        isDark
            ? Color(red: 0.155, green: 0.095, blue: 0.060)
            : Color(red: 0.345, green: 0.235, blue: 0.160)
    }

    private var mutedBlue: Color {
        isDark
            ? Color(red: 0.055, green: 0.085, blue: 0.125)
            : Color(red: 0.155, green: 0.230, blue: 0.300)
    }

    private var deepBlue: Color {
        isDark
            ? Color(red: 0.032, green: 0.047, blue: 0.070)
            : Color(red: 0.095, green: 0.125, blue: 0.160)
    }

    private var fluidGradient: some View {
        ZStack {
            LinearGradient(
                colors: [
                    baseColor,
                    mutedOrange.opacity(isDark ? 0.78 : 0.92),
                    mutedBlue.opacity(isDark ? 0.82 : 0.95),
                    deepBlue,
                ],
                startPoint: animated ? .topTrailing : .topLeading,
                endPoint: animated ? .bottomLeading : .bottomTrailing
            )

            AngularGradient(
                colors: [
                    mutedOrange.opacity(isDark ? 0.20 : 0.30),
                    mutedBlue.opacity(isDark ? 0.18 : 0.28),
                    deepBlue.opacity(isDark ? 0.26 : 0.34),
                    mutedOrange.opacity(isDark ? 0.14 : 0.22),
                    mutedOrange.opacity(isDark ? 0.20 : 0.30),
                ],
                center: animated ? .bottomTrailing : .topLeading
            )
            .scaleEffect(animated ? 1.18 : 1.05)
            .rotationEffect(.degrees(animated ? 10 : -8))
            .opacity(isDark ? 0.56 : 0.66)
        }
        .overlay(Color.black.opacity(isDark ? 0.28 : 0.16))
    }
}
