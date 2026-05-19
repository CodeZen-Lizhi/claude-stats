import AtollEmbed
import SwiftUI

struct NotchIslandModulePreview: View {
    let tab: NotchIslandSettingsTab
    let preferences: Preferences
    let refreshToken: Int

    var body: some View {
        let _ = refreshToken

        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Preview")
                    .font(.sora(13, weight: .semibold))
                Spacer()
                Text(previewStatus)
                    .font(.sora(10, weight: .medium))
                    .foregroundStyle(Color.stxMuted)
            }

            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.stxStroke, lineWidth: 1)
                    }

                VStack(spacing: 12) {
                    islandPill
                    previewContent
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 16)
            }
            .frame(height: 210)
        }
    }

    private var previewStatus: String {
        if !preferences.notchIslandEnabled {
            return "Disabled"
        }
        if let module = tab.module {
            return preferences.notchIslandEnabledModules.contains(module) ? "Enabled" : "Off"
        }
        return preferences.notchIslandSizePreset.displayName
    }

    private var islandPill: some View {
        HStack(spacing: 8) {
            Image(systemName: tab.symbol)
                .font(.system(size: 12, weight: .semibold))

            Text(tab.title)
                .font(.sora(11, weight: .semibold))
                .lineLimit(1)

            if preferences.notchIslandHoverExpansionEnabled {
                Circle()
                    .fill(Color.green.opacity(0.85))
                    .frame(width: 6, height: 6)
            }
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, 14)
        .frame(width: pillWidth, height: 34)
        .background(Color.black, in: Capsule())
        .shadow(color: Color.black.opacity(0.22), radius: 8, y: 4)
        .opacity(preferences.notchIslandEnabled ? 1 : 0.42)
    }

    @ViewBuilder
    private var previewContent: some View {
        switch tab {
        case .island, .appearance:
            generalPreview
        case .media:
            mediaPreview
        case .stats:
            statsPreview
        case .timer:
            timerPreview
        case .terminal:
            terminalPreview
        case .clipboard:
            listPreview(title: "Clipboard", rows: ["Copied prompt", "Terminal command", "JSON payload"])
        case .colorPicker:
            colorPickerPreview
        case .calendar:
            listPreview(title: "Calendar", rows: ["Design review", "Focus block", "Release notes"])
        case .shelf:
            shelfPreview
        case .privacy:
            chipsPreview(title: "Privacy", chips: [("Camera", "web.camera"), ("Mic", "mic.fill"), ("Caps", "capslock.fill")])
        case .recording:
            chipsPreview(title: "Recording", chips: [("Screen", "record.circle"), ("Hidden", "eye.slash")])
        case .focus:
            chipsPreview(title: "Focus", chips: [("Deep Work", "moon.fill"), ("Brief toast", "timer")])
        case .battery:
            batteryPreview
        case .bluetooth:
            chipsPreview(title: "Bluetooth", chips: [("AirPods", "headphones"), ("82%", "battery.75percent")])
        case .downloads:
            downloadPreview
        case .osd:
            osdPreview
        case .lockScreenWidgets:
            lockScreenPreview
        case .extensionBridge:
            chipsPreview(title: "Extensions", chips: [("Live", "bolt.fill"), ("Widgets", "rectangle.on.rectangle"), ("Tabs", "puzzlepiece.extension")])
        case .screenAssistant:
            chipsPreview(title: "Assistant", chips: [("Panel", "sparkles"), ("Local", "desktopcomputer")])
        }
    }

    private var generalPreview: some View {
        HStack(spacing: 10) {
            previewMetric("Mode", preferences.notchIslandDisplayMode.displayName)
            previewMetric("Size", preferences.notchIslandSizePreset.displayName)
            previewMetric("Modules", "\(preferences.notchIslandEnabledModules.count)")
            previewMetric("Shortcut", preferences.notchIslandShortcutEnabled ? "On" : "Off")
        }
    }

    private var mediaPreview: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.pink.opacity(0.8), .orange.opacity(0.75), .purple.opacity(0.72)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 62, height: 62)
                .overlay(Image(systemName: "music.note").foregroundStyle(.white))

            VStack(alignment: .leading, spacing: 7) {
                Text(stringValue("media.mediaController", fallback: "Now Playing"))
                    .font(.sora(12, weight: .semibold))
                Text(boolValue("media.enableLyrics") ? "Lyrics ready" : "Instrumental preview")
                    .font(.sora(10))
                    .foregroundStyle(Color.stxMuted)
                ProgressView(value: boolValue("media.showLiveCanvasInDynamicIsland") ? 0.72 : 0.42)
                    .tint(Color.stxAccent)
            }

            Spacer()
        }
    }

    private var statsPreview: some View {
        HStack(spacing: 8) {
            if boolValue("stats.showCpuGraph") {
                statTile("CPU", "42%", .green)
            }
            if boolValue("stats.showMemoryGraph") {
                statTile("MEM", "64%", .blue)
            }
            if boolValue("stats.showGpuGraph") {
                statTile("GPU", "31%", .purple)
            }
            if boolValue("stats.showNetworkGraph") {
                statTile("NET", "1.8M", .cyan)
            }
            if boolValue("stats.showDiskGraph") {
                statTile("DISK", "92K", .orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var timerPreview: some View {
        let ring = stringValue("timer.timerProgressStyle", fallback: "Bar") == "Ring"
        return HStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.11), lineWidth: 7)
                Circle()
                    .trim(from: 0, to: 0.68)
                    .stroke(Color.stxAccent, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("06")
                    .font(.sora(16, weight: .semibold).monospacedDigit())
            }
            .frame(width: ring ? 62 : 44, height: ring ? 62 : 44)

            VStack(alignment: .leading, spacing: 6) {
                Text("Timer")
                    .font(.sora(12, weight: .semibold))
                Text(stringValue("timer.timerDisplayMode", fallback: "tab").capitalized)
                    .font(.sora(10))
                    .foregroundStyle(Color.stxMuted)
                if !ring {
                    ProgressView(value: 0.68)
                        .tint(Color.stxAccent)
                        .frame(width: 140)
                }
            }
            Spacer()
        }
    }

    private var terminalPreview: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(stringValue("terminal.terminalShellPath", fallback: "/bin/zsh"))
                    .font(.sora(10, weight: .semibold).monospacedDigit())
                Spacer()
                Text("\(Int(doubleValue("terminal.terminalFontSize", fallback: 12))) pt")
                    .font(.sora(10).monospacedDigit())
                    .foregroundStyle(Color.stxMuted)
            }
            Text("$ codex-stats --notch")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
            Text("preview updated")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Color.green)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(doubleValue("terminal.terminalOpacity", fallback: 1)), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .foregroundStyle(Color.white)
    }

    private var colorPickerPreview: some View {
        let colors = [Color.red, Color.orange, Color.yellow, Color.green, Color.blue, Color.purple]
        return HStack(spacing: 10) {
            ForEach(colors.indices, id: \.self) { index in
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(colors[index])
                    .frame(width: 38, height: 54)
            }
            Spacer()
        }
    }

    private var shelfPreview: some View {
        HStack(spacing: 10) {
            ForEach(["doc.fill", "photo.fill", "folder.fill"], id: \.self) { symbol in
                VStack(spacing: 8) {
                    Image(systemName: symbol)
                        .font(.system(size: 19, weight: .semibold))
                    Text(boolValue("shelf.copyOnDrag") ? "Copy" : "Move")
                        .font(.sora(9, weight: .medium))
                }
                .frame(width: 74, height: 70)
                .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            Spacer()
        }
    }

    private var batteryPreview: some View {
        HStack(spacing: 12) {
            Image(systemName: "battery.75percent")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Color.green)
            VStack(alignment: .leading, spacing: 7) {
                Text(boolValue("battery.showBatteryPercentage") ? "76%" : "Charging")
                    .font(.sora(18, weight: .semibold).monospacedDigit())
                ProgressView(value: 0.76)
                    .tint(Color.green)
                    .frame(width: 170)
            }
            Spacer()
        }
    }

    private var downloadPreview: some View {
        HStack(spacing: 14) {
            Image(systemName: stringValue("downloads.selectedDownloadIndicatorStyle", fallback: "Progress") == "Circle" ? "arrow.down.circle" : "arrow.down.to.line")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Color.stxAccent)
            VStack(alignment: .leading, spacing: 8) {
                Text("Download")
                    .font(.sora(12, weight: .semibold))
                ProgressView(value: 0.58)
                    .tint(Color.stxAccent)
                    .frame(width: 180)
            }
            Spacer()
        }
    }

    private var osdPreview: some View {
        HStack(spacing: 14) {
            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: 22, weight: .semibold))
            ProgressView(value: 0.64)
                .tint(boolValue("osd.systemEventIndicatorUseAccent") ? Color.stxAccent : Color.primary)
                .frame(width: 190)
            Text(boolValue("osd.showProgressPercentages") ? "64%" : "")
                .font(.sora(12, weight: .semibold).monospacedDigit())
                .frame(width: 36, alignment: .trailing)
        }
        .padding(16)
        .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var lockScreenPreview: some View {
        HStack(spacing: 10) {
            previewMetric("Weather", boolValue("lockScreen.enableLockScreenWeatherWidget") ? "On" : "Off")
            previewMetric("Temp", stringValue("lockScreen.lockScreenWeatherTemperatureUnit", fallback: "Celsius"))
            previewMetric("Battery", boolValue("lockScreen.lockScreenBatteryShowsBatteryGauge") ? "Gauge" : "Hidden")
        }
    }

    private func listPreview(title: String, rows: [String]) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.sora(12, weight: .semibold))
            ForEach(rows, id: \.self) { row in
                HStack {
                    Circle()
                        .fill(Color.stxAccent.opacity(0.75))
                        .frame(width: 5, height: 5)
                    Text(row)
                        .font(.sora(10))
                        .foregroundStyle(Color.stxMuted)
                    Spacer()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chipsPreview(title: String, chips: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.sora(12, weight: .semibold))
            HStack(spacing: 8) {
                ForEach(chips, id: \.0) { chip in
                    Label(chip.0, systemImage: chip.1)
                        .font(.sora(10, weight: .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                }
                Spacer()
            }
        }
    }

    private func previewMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title.uppercased())
                .font(.sora(8, weight: .semibold))
                .tracking(0.7)
                .foregroundStyle(Color.stxMuted)
            Text(value)
                .font(.sora(14, weight: .semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func statTile(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.sora(8, weight: .semibold))
                .foregroundStyle(Color.stxMuted)
            Text(value)
                .font(.sora(14, weight: .semibold).monospacedDigit())
            RoundedRectangle(cornerRadius: 3)
                .fill(color.opacity(0.75))
                .frame(height: 24)
        }
        .padding(9)
        .frame(maxWidth: .infinity)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private var pillWidth: CGFloat {
        switch preferences.notchIslandSizePreset {
        case .compact: 150
        case .regular: 190
        case .large: 230
        }
    }

    private func boolValue(_ id: String) -> Bool {
        guard case .bool(let value) = AtollSettingsBridge.value(for: id) else { return false }
        return value
    }

    private func doubleValue(_ id: String, fallback: Double) -> Double {
        switch AtollSettingsBridge.value(for: id) {
        case .double(let value): value
        case .int(let value): Double(value)
        default: fallback
        }
    }

    private func stringValue(_ id: String, fallback: String) -> String {
        switch AtollSettingsBridge.value(for: id) {
        case .string(let value): value
        case .int(let value): String(value)
        case .double(let value): String(Int(value.rounded()))
        default: fallback
        }
    }
}
