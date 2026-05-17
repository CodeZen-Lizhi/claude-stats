import SwiftUI

private struct TerminalEntranceModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let cornerRadius: CGFloat
    @State private var appeared = false
    @State private var highlight = false

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .scaleEffect(reduceMotion || appeared ? 1 : 0.985)
            .offset(y: reduceMotion || appeared ? 0 : 8)
            .blur(radius: reduceMotion || appeared ? 0 : 2)
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(highlight ? 0.22 : 0), lineWidth: 1)
            }
            .animation(.spring(response: 0.42, dampingFraction: 0.86), value: appeared)
            .onAppear(perform: start)
    }

    private func start() {
        guard !appeared else { return }
        if reduceMotion {
            appeared = true
            return
        }

        appeared = true
        highlight = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 280_000_000)
            withAnimation(.easeOut(duration: 0.36)) {
                highlight = false
            }
        }
    }
}

extension View {
    func terminalEntrance(cornerRadius: CGFloat) -> some View {
        modifier(TerminalEntranceModifier(cornerRadius: cornerRadius))
    }
}
