import SwiftUI

struct AppSwitchToggleStyle: ToggleStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        Button {
            guard isEnabled else { return }
            withAnimation(motionAnimation) {
                configuration.isOn.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                configuration.label

                switchTrack(isOn: configuration.isOn)
            }
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.48)
        .animation(motionAnimation, value: configuration.isOn)
    }

    private func switchTrack(isOn: Bool) -> some View {
        ZStack {
            Capsule()
                .fill(isOn ? Color.stxAccent : Color.primary.opacity(0.14))
                .overlay {
                    if isOn {
                        DiagonalStripes(spacing: 4)
                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                            .clipShape(Capsule())
                    }
                }
                .overlay {
                    Capsule()
                        .strokeBorder(trackStroke(isOn: isOn), lineWidth: 1)
                }

            Circle()
                .fill(Color.white)
                .frame(width: 20, height: 20)
                .shadow(color: Color.black.opacity(0.16), radius: 1.5, x: 0, y: 1)
                .offset(x: isOn ? 9 : -9)
        }
        .frame(width: 42, height: 24)
        .contentShape(Capsule())
    }

    private func trackStroke(isOn: Bool) -> Color {
        isOn ? Color.white.opacity(0.18) : Color.primary.opacity(0.18)
    }

    private var motionAnimation: Animation? {
        reduceMotion ? nil : .timingCurve(0.42, 0.00, 0.20, 1.00, duration: 0.32)
    }
}

extension ToggleStyle where Self == AppSwitchToggleStyle {
    static var appSwitch: AppSwitchToggleStyle { AppSwitchToggleStyle() }
}
