import SwiftUI

enum BoringBeamAvatar {
    static let defaultColors = [
        "#92A1C6",
        "#146A7C",
        "#F0AB3D",
        "#C271B4",
        "#C20D90",
    ]

    static let size: CGFloat = 36

    struct Data: Sendable, Equatable {
        let wrapperColor: String
        let faceColor: String
        let backgroundColor: String
        let wrapperTranslateX: CGFloat
        let wrapperTranslateY: CGFloat
        let wrapperRotate: CGFloat
        let wrapperScale: CGFloat
        let isMouthOpen: Bool
        let isCircle: Bool
        let eyeSpread: CGFloat
        let mouthSpread: CGFloat
        let faceRotate: CGFloat
        let faceTranslateX: CGFloat
        let faceTranslateY: CGFloat
    }

    static func generate(name: String, colors: [String] = defaultColors) -> Data {
        let palette = colors.isEmpty ? defaultColors : colors
        let numFromName = hashCode(name)
        let range = palette.count
        let wrapperColor = randomColor(number: numFromName, colors: palette, range: range)
        let preTranslateX = unit(number: numFromName, range: 10, index: 1)
        let preTranslateY = unit(number: numFromName, range: 10, index: 2)
        let wrapperTranslateX = preTranslateX < 5 ? preTranslateX + size / 9 : preTranslateX
        let wrapperTranslateY = preTranslateY < 5 ? preTranslateY + size / 9 : preTranslateY

        return Data(
            wrapperColor: wrapperColor,
            faceColor: contrast(for: wrapperColor),
            backgroundColor: randomColor(number: numFromName + 13, colors: palette, range: range),
            wrapperTranslateX: wrapperTranslateX,
            wrapperTranslateY: wrapperTranslateY,
            wrapperRotate: unit(number: numFromName, range: 360),
            wrapperScale: 1 + unit(number: numFromName, range: Int(size / 12)) / 10,
            isMouthOpen: bool(number: numFromName, index: 2),
            isCircle: bool(number: numFromName, index: 1),
            eyeSpread: unit(number: numFromName, range: 5),
            mouthSpread: unit(number: numFromName, range: 3),
            faceRotate: unit(number: numFromName, range: 10, index: 3),
            faceTranslateX: wrapperTranslateX > size / 6 ? wrapperTranslateX / 2 : unit(number: numFromName, range: 8, index: 1),
            faceTranslateY: wrapperTranslateY > size / 6 ? wrapperTranslateY / 2 : unit(number: numFromName, range: 7, index: 2)
        )
    }

    static func contrast(for hexColor: String) -> String {
        let hex = hexColor.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard hex.count == 6,
              let value = Int(hex, radix: 16) else {
            return "#000000"
        }
        let r = (value >> 16) & 0xff
        let g = (value >> 8) & 0xff
        let b = value & 0xff
        let yiq = ((r * 299) + (g * 587) + (b * 114)) / 1000
        return yiq >= 128 ? "#000000" : "#FFFFFF"
    }

    static func color(_ hexColor: String) -> Color {
        let hex = hexColor.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard hex.count == 6,
              let value = Int(hex, radix: 16) else {
            return .primary
        }
        return Color(
            red: Double((value >> 16) & 0xff) / 255,
            green: Double((value >> 8) & 0xff) / 255,
            blue: Double(value & 0xff) / 255
        )
    }

    private static func hashCode(_ name: String) -> Int {
        var hash: Int32 = 0
        for scalar in name.unicodeScalars {
            hash = hash &* 31 &+ Int32(bitPattern: scalar.value)
        }
        return Int(abs(Int64(hash)))
    }

    private static func digit(number: Int, index: Int) -> Int {
        Int(floor(Double(number) / pow(10, Double(index)))) % 10
    }

    private static func bool(number: Int, index: Int) -> Bool {
        digit(number: number, index: index).isMultiple(of: 2)
    }

    private static func unit(number: Int, range: Int, index: Int? = nil) -> CGFloat {
        let value = CGFloat(number % range)
        guard let index,
              digit(number: number, index: index).isMultiple(of: 2) else {
            return value
        }
        return -value
    }

    private static func randomColor(number: Int, colors: [String], range: Int) -> String {
        colors[number % range]
    }
}

struct BeamAvatarView: View {
    let seed: String
    var size: CGFloat = 32
    var square = false
    var isDecorative = true

    private var data: BoringBeamAvatar.Data {
        BoringBeamAvatar.generate(name: seed)
    }

    var body: some View {
        Canvas { context, canvasSize in
            let scale = min(canvasSize.width, canvasSize.height) / BoringBeamAvatar.size
            var context = context
            context.scaleBy(x: scale, y: scale)

            if square {
                context.clip(to: Path(CGRect(x: 0, y: 0, width: BoringBeamAvatar.size, height: BoringBeamAvatar.size)))
            } else {
                context.clip(to: Path(ellipseIn: CGRect(x: 0, y: 0, width: BoringBeamAvatar.size, height: BoringBeamAvatar.size)))
            }

            context.fill(
                Path(CGRect(x: 0, y: 0, width: BoringBeamAvatar.size, height: BoringBeamAvatar.size)),
                with: .color(BoringBeamAvatar.color(data.backgroundColor))
            )

            drawWrapper(in: &context)
            drawFace(in: &context)
        }
        .frame(width: size, height: size)
        .overlay(
            Circle()
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .accessibilityHidden(isDecorative)
        .accessibilityLabel(Text("Generated Beam avatar"))
    }

    private func drawWrapper(in context: inout GraphicsContext) {
        var wrapper = context
        wrapper.translateBy(x: data.wrapperTranslateX, y: data.wrapperTranslateY)
        wrapper.translateBy(x: BoringBeamAvatar.size / 2, y: BoringBeamAvatar.size / 2)
        wrapper.rotate(by: .degrees(data.wrapperRotate))
        wrapper.scaleBy(x: data.wrapperScale, y: data.wrapperScale)
        wrapper.translateBy(x: -BoringBeamAvatar.size / 2, y: -BoringBeamAvatar.size / 2)

        let radius = data.isCircle ? BoringBeamAvatar.size : BoringBeamAvatar.size / 6
        wrapper.fill(
            Path(roundedRect: CGRect(x: 0, y: 0, width: BoringBeamAvatar.size, height: BoringBeamAvatar.size), cornerRadius: radius),
            with: .color(BoringBeamAvatar.color(data.wrapperColor))
        )
    }

    private func drawFace(in context: inout GraphicsContext) {
        var face = context
        face.translateBy(x: data.faceTranslateX, y: data.faceTranslateY)
        face.translateBy(x: BoringBeamAvatar.size / 2, y: BoringBeamAvatar.size / 2)
        face.rotate(by: .degrees(data.faceRotate))
        face.translateBy(x: -BoringBeamAvatar.size / 2, y: -BoringBeamAvatar.size / 2)

        let faceColor = BoringBeamAvatar.color(data.faceColor)
        let mouthY = 19 + data.mouthSpread
        if data.isMouthOpen {
            var mouth = Path()
            mouth.move(to: CGPoint(x: 15, y: mouthY))
            mouth.addCurve(
                to: CGPoint(x: 21, y: mouthY),
                control1: CGPoint(x: 17, y: mouthY + 1),
                control2: CGPoint(x: 19, y: mouthY + 1)
            )
            face.stroke(mouth, with: .color(faceColor), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        } else {
            var mouth = Path()
            mouth.move(to: CGPoint(x: 13, y: mouthY))
            mouth.addQuadCurve(to: CGPoint(x: 23, y: mouthY), control: CGPoint(x: 18, y: mouthY + 1.5))
            mouth.addQuadCurve(to: CGPoint(x: 13, y: mouthY), control: CGPoint(x: 18, y: mouthY + 0.25))
            face.fill(mouth, with: .color(faceColor))
        }

        face.fill(eyeRect(x: 14 - data.eyeSpread), with: .color(faceColor))
        face.fill(eyeRect(x: 20 + data.eyeSpread), with: .color(faceColor))
    }

    private func eyeRect(x: CGFloat) -> Path {
        Path(roundedRect: CGRect(x: x, y: 14, width: 1.5, height: 2), cornerRadius: 1)
    }
}

#if DEBUG
#Preview("Beam avatars") {
    HStack(spacing: 12) {
        BeamAvatarView(seed: "avatar-a", size: 52)
        BeamAvatarView(seed: "avatar-b", size: 52)
        BeamAvatarView(seed: "avatar-c", size: 52)
    }
    .padding(24)
    .background(Color.stxBackground)
}
#endif
