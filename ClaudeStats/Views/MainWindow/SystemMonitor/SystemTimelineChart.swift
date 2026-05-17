import SwiftUI

struct SystemTimelineSegment {
    var value: Double
    var color: Color
}

struct SystemTimelineChart: View {
    var bars: [[SystemTimelineSegment]]
    var placeholderCount: Int = 48

    var body: some View {
        Canvas { context, size in
            let displayBars = bars.isEmpty ? placeholderBars : bars
            let count = max(1, displayBars.count)
            let spacing: CGFloat = 2
            let width = max(1, (size.width - CGFloat(count - 1) * spacing) / CGFloat(count))

            for (index, segments) in displayBars.enumerated() {
                let x = CGFloat(index) * (width + spacing)
                var y = size.height
                for segment in segments {
                    let value = min(1, max(0, segment.value))
                    let height = max(value * size.height, value > 0 ? 1 : 0)
                    y -= height
                    let rect = CGRect(x: x, y: y, width: width, height: height)
                    context.fill(Path(roundedRect: rect, cornerRadius: min(2, width / 2)), with: .color(segment.color))
                }
            }
        }
        .frame(height: 72)
        .accessibilityHidden(true)
    }

    private var placeholderBars: [[SystemTimelineSegment]] {
        (0..<placeholderCount).map { index in
            let value = 0.12 + (Double(index % 7) * 0.015)
            return [SystemTimelineSegment(value: value, color: Color.primary.opacity(0.10))]
        }
    }
}

struct SystemCoreLoadStrip: View {
    var values: [Double]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(values.prefix(24).enumerated()), id: \.offset) { _, value in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(coreColor(value))
                    .frame(maxWidth: .infinity)
                    .frame(height: 18)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(Color.black.opacity(0.10))
                            .frame(height: max(1, 18 * CGFloat(1 - min(1, max(0, value)))))
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
            }
        }
        .frame(height: 18)
        .accessibilityLabel("Per-core CPU load")
    }

    private func coreColor(_ value: Double) -> Color {
        switch value {
        case 0.75...: Color.stxRamp[0]
        case 0.45...: Color.stxRamp[1]
        default: Color.stxRamp[3]
        }
    }
}
