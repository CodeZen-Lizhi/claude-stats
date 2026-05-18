import SwiftUI

struct NotchIslandRootView: View {
    @Environment(AppEnvironment.self) private var env

    let runtime: NotchIslandRuntime
    var onHoverChanged: (Bool) -> Void
    var onCollapseRequested: () -> Void

    var body: some View {
        @Bindable var runtime = runtime
        let shape = RoundedRectangle(cornerRadius: runtime.isExpanded ? 28 : 20, style: .continuous)

        ZStack {
            if runtime.isExpanded {
                expandedContent
                    .transition(.opacity.combined(with: .scale(scale: 0.985, anchor: .top)))
            } else {
                compactContent
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black, in: shape)
        .overlay(shape.stroke(Color.white.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(runtime.isExpanded ? 0.34 : 0.18), radius: runtime.isExpanded ? 24 : 10, y: 12)
        .contentShape(Rectangle())
        .onHover { hovering in
            guard env.preferences.notchIslandHoverExpansionEnabled else { return }
            onHoverChanged(hovering)
        }
        .font(.sora(12))
        .tint(.stxAccent)
        .animation(.easeOut(duration: 0.16), value: runtime.selectedModule)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Notch Island")
    }

    private var compactContent: some View {
        HStack(spacing: 9) {
            Image(systemName: runtime.selectedModule.symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.stxAccent)
                .frame(width: 18)
            Text(runtime.selectedModule.title)
                .font(.sora(12, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Spacer(minLength: 4)
            compactMetric
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
    }

    @ViewBuilder
    private var compactMetric: some View {
        switch runtime.selectedModule {
        case .stats:
            let cpu = runtime.systemSnapshot?.cpu.totalUsage ?? 0
            Text(Format.percent(cpu))
                .font(.sora(11, weight: .medium).monospacedDigit())
                .foregroundStyle(Color.white.opacity(0.72))
        case .battery:
            if let level = runtime.systemSnapshot?.battery.level {
                Text(Format.percent(level))
                    .font(.sora(11, weight: .medium).monospacedDigit())
                    .foregroundStyle(Color.white.opacity(0.72))
            }
        case .timer:
            Text(timerText(runtime.timerRemainingSeconds))
                .font(.sora(11, weight: .medium).monospacedDigit())
                .foregroundStyle(Color.white.opacity(0.72))
        default:
            Circle()
                .fill(Color.white.opacity(0.42))
                .frame(width: 6, height: 6)
        }
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            moduleStrip
            moduleContent
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 16)
        .foregroundStyle(.white)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "capsule.portrait.tophalf.filled")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.stxAccent)
            VStack(alignment: .leading, spacing: 2) {
                Text("NOTCH ISLAND")
                    .font(.sora(10, weight: .semibold))
                    .tracking(1.1)
                    .foregroundStyle(Color.white.opacity(0.62))
                Text(runtime.activeStatusText)
                    .font(.sora(12, weight: .medium))
                    .lineLimit(1)
                    .foregroundStyle(.white)
            }
            Spacer()
            Button {
                onCollapseRequested()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 26, height: 24)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .help("Collapse")
        }
    }

    private var moduleStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(runtime.enabledModules) { module in
                    Button {
                        runtime.selectedModule = module
                        if module == .clipboard {
                            runtime.refreshClipboardPreview()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: module.symbol)
                                .font(.system(size: 11, weight: .semibold))
                            Text(module.title)
                                .font(.sora(10, weight: .medium))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            runtime.selectedModule == module ? Color.white.opacity(0.16) : Color.white.opacity(0.07),
                            in: Capsule()
                        )
                        .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .help(module.settingsDescription)
                }
            }
            .padding(.vertical, 1)
        }
    }

    @ViewBuilder
    private var moduleContent: some View {
        switch runtime.selectedModule {
        case .stats:
            statsContent
        case .timer:
            timerContent
        case .clipboard:
            clipboardContent
        case .colorPicker:
            colorPickerContent
        case .battery:
            batteryContent
        case .privacy:
            sourceLinkedContent(
                title: "Privacy indicators",
                detail: "Camera and microphone detection is wired as an Atoll-backed module and stays permission-gated.",
                module: .privacy
            )
        case .terminal:
            sourceLinkedContent(
                title: "Terminal",
                detail: "This module is reserved for the existing Ghostty-backed terminal surface.",
                module: .terminal
            )
        default:
            sourceLinkedContent(
                title: runtime.selectedModule.title,
                detail: runtime.selectedModule.settingsDescription,
                module: runtime.selectedModule
            )
        }
    }

    private var statsContent: some View {
        let snapshot = runtime.systemSnapshot ?? .placeholder
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 128), spacing: 10)], spacing: 10) {
            NotchMetricTile(title: "CPU", value: Format.percent(snapshot.cpu.totalUsage), symbol: "cpu")
            NotchMetricTile(title: "Memory", value: Format.percent(snapshot.memory.usedRatio), symbol: "memorychip")
            NotchMetricTile(title: "Disk", value: Format.percent(snapshot.disk.usedRatio), symbol: "internaldrive")
            NotchMetricTile(title: "Network", value: bytesPerSecond(snapshot.network.downloadBytesPerSecond), symbol: "arrow.down")
            NotchMetricTile(title: "Thermal", value: snapshot.thermal.state.displayName, symbol: "thermometer.medium")
            NotchMetricTile(title: "GPU", value: snapshot.gpu.utilization.map(Format.percent) ?? "N/A", symbol: "display")
        }
    }

    private var batteryContent: some View {
        let battery = runtime.systemSnapshot?.battery ?? .placeholder
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                NotchMetricTile(title: "Level", value: battery.level.map(Format.percent) ?? "N/A", symbol: "battery.75percent")
                NotchMetricTile(title: "Power", value: battery.powerSource, symbol: battery.isBatteryPowered ? "bolt.slash" : "bolt")
                NotchMetricTile(title: "Cycles", value: battery.cycleCount.map(String.init) ?? "N/A", symbol: "arrow.triangle.2.circlepath")
            }
            if battery.isCharging || battery.isCharged {
                Text(battery.isCharged ? "Charged" : "Charging")
                    .font(.sora(11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.68))
            }
        }
    }

    private var timerContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(timerText(runtime.timerRemainingSeconds))
                    .font(.sora(42, weight: .semibold).monospacedDigit())
                Text(runtime.timerRunning ? "RUNNING" : "READY")
                    .font(.sora(10, weight: .semibold))
                    .tracking(1.1)
                    .foregroundStyle(Color.white.opacity(0.58))
            }
            HStack(spacing: 8) {
                Button(runtime.timerRunning ? "Pause" : "Start") {
                    runtime.timerRunning ? runtime.stopTimer() : runtime.startTimer()
                }
                .buttonStyle(.borderedProminent)

                Button("Reset") {
                    runtime.resetTimer()
                }
                .buttonStyle(.bordered)

                ForEach([5, 15, 30], id: \.self) { minutes in
                    Button("\(minutes)m") {
                        runtime.setTimer(minutes: minutes)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var clipboardContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(runtime.clipboardPreview)
                .font(.sora(13))
                .lineLimit(4)
                .foregroundStyle(Color.white.opacity(0.84))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            Button {
                runtime.refreshClipboardPreview()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
        }
    }

    private var colorPickerContent: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(hex: runtime.selectedColorHex) ?? Color.stxAccent)
                .frame(width: 72, height: 72)
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.white.opacity(0.16), lineWidth: 1))
            VStack(alignment: .leading, spacing: 8) {
                Text(runtime.selectedColorHex)
                    .font(.sora(18, weight: .semibold).monospaced())
                Button {
                    runtime.openColorPanel()
                } label: {
                    Label("Open Color Panel", systemImage: "eyedropper")
                }
                .buttonStyle(.bordered)
            }
            Spacer()
        }
    }

    private func sourceLinkedContent(title: String, detail: String, module: NotchIslandModule) -> some View {
        let descriptor = NotchIslandFeatureRegistry.descriptor(for: module)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: module.symbol)
                    .foregroundStyle(Color.stxAccent)
                Text(title)
                    .font(.sora(16, weight: .semibold))
            }
            Text(detail)
                .font(.sora(12))
                .foregroundStyle(Color.white.opacity(0.68))
                .fixedSize(horizontal: false, vertical: true)
            Text(descriptor.statusText)
                .font(.sora(10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Color.white.opacity(0.52))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func timerText(_ seconds: Int) -> String {
        let safeSeconds = max(0, seconds)
        let hours = safeSeconds / 3600
        let minutes = (safeSeconds % 3600) / 60
        let remainder = safeSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainder)
        }
        return String(format: "%02d:%02d", minutes, remainder)
    }

    private func bytesPerSecond(_ value: Double) -> String {
        "\(Format.bytes(Int(clamping: UInt64(max(0, value.rounded())))))/s"
    }
}

private struct NotchMetricTile: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.stxAccent)
                Text(title)
                    .font(.sora(10, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.58))
                    .lineLimit(1)
            }
            Text(value)
                .font(.sora(16, weight: .semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.68)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.white.opacity(0.1), lineWidth: 1))
    }
}

private extension Color {
    init?(hex: String) {
        let trimmed = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard trimmed.count == 6, let value = Int(trimmed, radix: 16) else { return nil }
        let red = Double((value >> 16) & 0xFF) / 255
        let green = Double((value >> 8) & 0xFF) / 255
        let blue = Double(value & 0xFF) / 255
        self.init(red: red, green: green, blue: blue)
    }
}

#if DEBUG
#Preview("Notch Island") {
    VStack(spacing: 24) {
        NotchIslandRootView(runtime: NotchIslandRuntime(), onHoverChanged: { _ in }, onCollapseRequested: {})
            .frame(width: 246, height: 38)
        NotchIslandRootView(runtime: {
            let runtime = NotchIslandRuntime()
            runtime.isExpanded = true
            return runtime
        }(), onHoverChanged: { _ in }, onCollapseRequested: {})
        .frame(width: 640, height: 340)
    }
    .padding(40)
    .background(Color.stxBackground)
    .environment(AppEnvironment.preview())
}
#endif
