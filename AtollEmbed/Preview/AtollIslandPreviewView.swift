import AppKit
import SwiftUI
import ClaudeStatsIconography

public struct AtollIslandPreviewView: View {
    public let configuration: AtollIslandPreviewConfiguration
    public let sampleData: AtollIslandPreviewSampleData

    public init(
        configuration: AtollIslandPreviewConfiguration,
        sampleData: AtollIslandPreviewSampleData = .deterministic
    ) {
        self.configuration = configuration
        self.sampleData = sampleData
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 16) {
            AtollIslandClosedPreviewColumn(configuration: configuration, sampleData: sampleData)
                .frame(width: 190)

            AtollIslandOpenPreviewColumn(configuration: configuration, sampleData: sampleData)
                .frame(maxWidth: .infinity)
        }
        .padding(14)
        .accessibilityElement(children: .contain)
        .opacity(configuration.isFeatureEnabled ? 1 : 0.44)
    }
}

private struct AtollIslandClosedPreviewColumn: View {
    let configuration: AtollIslandPreviewConfiguration
    let sampleData: AtollIslandPreviewSampleData

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            previewLabel("Closed")

            AtollIslandPreviewShell(
                isDynamicIsland: configuration.settings.usesDynamicIslandShape,
                isOpen: false,
                enableShadow: configuration.settings.enableShadow
            ) {
                closedActivity
                    .frame(width: closedWidth, height: 34)
            }
            .frame(width: closedWidth, height: 34)
            .frame(maxWidth: .infinity)
            .opacity(configuration.isSelectedTabEnabled ? 1 : 0.62)

            closedSupplement
        }
    }

    @ViewBuilder
    private var closedActivity: some View {
        if !configuration.isSelectedTabEnabled {
            disabledClosedActivity
        } else {
            enabledClosedActivity
        }
    }

    @ViewBuilder
    private var enabledClosedActivity: some View {
        switch configuration.selectedTab {
        case .media, .appearance, .island:
            mediaClosedActivity
        case .stats:
            closedBadge(symbol: "cpu", title: "42%", tint: .blue)
        case .timer:
            timerClosedActivity
        case .clipboard:
            closedBadge(symbol: "doc.on.clipboard", title: "\(configuration.settings.clipboardHistorySize)", tint: .white.opacity(0.85))
        case .colorPicker:
            closedBadge(symbol: "eyedropper", title: "#F05A4F", tint: .orange)
        case .calendar:
            closedBadge(symbol: "calendar", title: "10:30", tint: .cyan)
        case .shelf:
            closedBadge(symbol: "tray.fill", title: "\(sampleData.shelfItems.count)", tint: .white.opacity(0.85))
        case .privacy:
            privacyClosedActivity
        case .recording:
            closedBadge(symbol: "record.circle.fill", title: "REC", tint: .red)
        case .focus:
            closedBadge(symbol: "moon.fill", title: configuration.settings.showDoNotDisturbLabel ? "Focus" : "", tint: .indigo)
        case .battery:
            batteryClosedActivity
        case .bluetooth:
            closedBadge(symbol: "headphones", title: configuration.settings.showBluetoothBatteryPercentageText ? "82%" : "", tint: .blue)
        case .downloads:
            downloadClosedActivity
        case .osd:
            closedBadge(symbol: "speaker.wave.2.fill", title: configuration.settings.showProgressPercentages ? "64%" : "", tint: .accentColor)
        case .lockScreenWidgets:
            closedBadge(symbol: "lock.display", title: "Weather", tint: .mint)
        case .extensionBridge:
            closedBadge(symbol: "puzzlepiece.extension", title: "\(configuration.settings.extensionLiveActivityCapacity)", tint: .purple)
        case .screenAssistant:
            closedBadge(symbol: "sparkles", title: "Ask", tint: .yellow)
        case .terminal:
            closedBadge(symbol: "apple.terminal", title: "~", tint: .green)
        }
    }

    private var disabledClosedActivity: some View {
        HStack(spacing: 8) {
            FunctionalIconView(systemSymbolName: configuration.selectedTab.iconName)
                .font(.system(size: 13, weight: .semibold))
            Text("Off")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white.opacity(0.72))
        .padding(.horizontal, 12)
    }

    private var mediaClosedActivity: some View {
        HStack(spacing: 8) {
            artwork(size: 24, colors: sampleData.media.artworkColors)
            Rectangle()
                .fill(.black)
                .frame(maxWidth: .infinity)
            waveform(color: configuration.settings.coloredSpectrogram ? sampleData.media.artworkColors.last?.swiftUIColor ?? .orange : .gray)
                .frame(width: 42, height: 18)
        }
        .padding(.horizontal, 7)
    }

    private var timerClosedActivity: some View {
        HStack(spacing: 8) {
            timerRing(size: 24, lineWidth: 3, progress: sampleData.timer.progress, color: configuration.settings.timerSolidColor.swiftUIColor)
            Rectangle()
                .fill(.black)
                .frame(maxWidth: .infinity)
            if configuration.settings.timerShowsCountdown {
                Text(sampleData.timer.remaining)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
        .padding(.horizontal, 8)
    }

    private var privacyClosedActivity: some View {
        HStack(spacing: 8) {
            FunctionalIconView(systemSymbolName: "mic.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.orange)
            Rectangle()
                .fill(.black)
                .frame(maxWidth: .infinity)
            FunctionalIconView(systemSymbolName: "video.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.green)
        }
        .padding(.horizontal, 12)
    }

    private var batteryClosedActivity: some View {
        HStack(spacing: 7) {
            FunctionalIconView(systemSymbolName: "battery.75percent")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.green)
            Rectangle()
                .fill(.black)
                .frame(maxWidth: .infinity)
            if configuration.settings.showBatteryPercentage {
                Text("76%")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
        .padding(.horizontal, 10)
    }

    private var downloadClosedActivity: some View {
        HStack(spacing: 8) {
            FunctionalIconView(systemSymbolName: "arrow.down.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            Rectangle()
                .fill(.black)
                .frame(maxWidth: .infinity)
            if configuration.settings.selectedDownloadIndicatorStyle == "Circle" {
                FunctionalIconView(systemSymbolName: "circle.dotted")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            } else {
                tinyProgress(value: 0.58, color: .accentColor)
                    .frame(width: 42, height: 5)
            }
        }
        .padding(.horizontal, 10)
    }

    private func closedBadge(symbol: String, title: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            FunctionalIconView(systemSymbolName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
            Rectangle()
                .fill(.black)
                .frame(maxWidth: .infinity)
            if !title.isEmpty {
                Text(title)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
        }
        .padding(.horizontal, 11)
    }

    private var closedSupplement: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                statusChip(configuration.isSelectedTabEnabled ? "Enabled" : "Off", style: .ambient)
                if configuration.hoverExpansionEnabled {
                    statusChip("Hover", style: .ambient)
                }
            }

            switch configuration.selectedTab {
            case .media, .appearance, .island:
                supplementLine(sampleData.media.title, detail: configuration.settings.enableLyrics ? sampleData.media.lyric : sampleData.media.artist)
            case .stats:
                supplementLine("Live graphs", detail: "\(enabledMetricSamples.count) visible")
            case .timer:
                supplementLine(sampleData.timer.title, detail: sampleData.timer.remaining)
            case .clipboard:
                supplementLine("History", detail: "\(configuration.settings.clipboardHistorySize) items")
            case .colorPicker:
                supplementLine("Recent colors", detail: "\(configuration.settings.colorHistorySize) saved")
            case .calendar:
                supplementLine(sampleData.calendar.first?.title ?? "Event", detail: sampleData.calendar.first?.time ?? "Now")
            case .shelf:
                supplementLine(configuration.settings.copyOnDrag ? "Copy on drag" : "Move on drag", detail: configuration.settings.quickShareProvider)
            case .privacy:
                supplementLine("Camera + mic", detail: configuration.settings.enableCapsLockIndicator ? "Caps Lock ready" : "Indicators")
            case .recording:
                supplementLine("Recording", detail: "Hidden from capture")
            case .focus:
                supplementLine("Deep Work", detail: configuration.settings.focusIndicatorNonPersistent ? "Brief toast" : "Persistent")
            case .battery:
                supplementLine("Charging", detail: configuration.settings.lowBatteryHUDStyle.capitalized)
            case .bluetooth:
                supplementLine("AirPods", detail: "82% left")
            case .downloads:
                supplementLine("Package.dmg", detail: configuration.settings.selectedDownloadIndicatorStyle)
            case .osd:
                supplementLine("Volume", detail: configuration.settings.inlineHUD ? "Inline" : "HUD")
            case .lockScreenWidgets:
                supplementLine("Lock widgets", detail: configuration.settings.lockScreenWeatherTemperatureUnit)
            case .extensionBridge:
                supplementLine("Extensions", detail: "\(configuration.settings.extensionLiveActivityCapacity) live")
            case .screenAssistant:
                supplementLine("Assistant", detail: configuration.settings.selectedAIProvider)
            case .terminal:
                supplementLine(configuration.settings.terminalShellPath, detail: "\(Int(configuration.settings.terminalFontSize)) pt")
            }
        }
    }

    private var enabledMetricSamples: [AtollIslandPreviewSampleData.Metric] {
        sampleData.enabledMetrics(settings: configuration.settings)
    }

    private var closedWidth: CGFloat {
        switch configuration.sizePreset {
        case .compact: 138
        case .regular: 158
        case .large: 178
        }
    }
}

private struct AtollIslandOpenPreviewColumn: View {
    let configuration: AtollIslandPreviewConfiguration
    let sampleData: AtollIslandPreviewSampleData

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            previewLabel("Open")

            AtollIslandPreviewShell(
                isDynamicIsland: configuration.settings.usesDynamicIslandShape,
                isOpen: true,
                enableShadow: configuration.settings.enableShadow
            ) {
                VStack(spacing: 0) {
                    header
                        .frame(height: 40)
                    moduleContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
                .frame(width: openWidth, height: openHeight)
                .background(Color.black)
            }
            .frame(width: openWidth, height: openHeight)
            .frame(maxWidth: .infinity)
            .opacity(configuration.isSelectedTabEnabled ? 1 : 0.54)
            .overlay(alignment: .bottomTrailing) {
                if !configuration.isSelectedTabEnabled {
                    statusChip("Module off", style: .ambient)
                        .padding(12)
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 0) {
            HStack(spacing: 18) {
                ForEach(headerTabs) { tab in
                    AtollIslandPreviewHeaderTabView(tab: tab)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                if configuration.settings.showMirror {
                    headerRoundIcon("web.camera")
                }
                if configuration.settings.settingsIconInNotch {
                    headerRoundIcon("gearshape")
                }
                if configuration.selectedTab == .battery || configuration.enabledTabs.contains(.battery) {
                    headerBattery
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .foregroundStyle(.gray)
    }

    private var moduleContent: some View {
        Group {
            switch configuration.selectedTab {
            case .island, .appearance:
                overviewContent
            case .media:
                mediaContent
            case .stats:
                statsContent
            case .timer:
                timerContent
            case .clipboard:
                clipboardContent
            case .colorPicker:
                colorPickerContent
            case .calendar:
                calendarContent
            case .shelf:
                shelfContent
            case .privacy:
                privacyContent
            case .recording:
                recordingContent
            case .focus:
                focusContent
            case .battery:
                batteryContent
            case .bluetooth:
                bluetoothContent
            case .downloads:
                downloadsContent
            case .osd:
                osdContent
            case .lockScreenWidgets:
                lockScreenContent
            case .extensionBridge:
                extensionContent
            case .screenAssistant:
                screenAssistantContent
            case .terminal:
                terminalContent
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .foregroundStyle(.white)
    }

    private var overviewContent: some View {
        HStack(alignment: .top, spacing: 14) {
            artwork(size: 72, colors: sampleData.media.artworkColors)

            VStack(alignment: .leading, spacing: 9) {
                Text(configuration.settings.usesDynamicIslandShape ? "Dynamic Island" : "Standard Notch")
                    .font(.system(size: 18, weight: .semibold))
                Text("Tabs, media, and live activities share the same black Atoll shell.")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(2)
                HStack(spacing: 8) {
                    statusChip(configuration.sizePreset.rawValue.capitalized)
                    statusChip(configuration.hoverExpansionEnabled ? "Hover open" : "Manual")
                    statusChip(configuration.settings.cornerRadiusScaling ? "Scaled corners" : "Fixed corners")
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 10)
    }

    private var mediaContent: some View {
        HStack(alignment: .top, spacing: 14) {
            artwork(size: 78, colors: sampleData.media.artworkColors)

            VStack(alignment: .leading, spacing: 7) {
                Text(sampleData.media.title)
                    .font(.system(size: 17, weight: .semibold))
                    .lineLimit(1)
                Text(sampleData.media.artist)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(configuration.settings.playerColorTinting ? sampleData.media.artworkColors.first?.swiftUIColor ?? .gray : .gray)
                    .lineLimit(1)
                if configuration.settings.enableLyrics {
                    Text(sampleData.media.lyric)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(1)
                }

                tinyProgress(value: sampleData.media.progress, color: sampleData.media.artworkColors.last?.swiftUIColor ?? .accentColor)
                    .frame(height: 6)

                HStack(spacing: 10) {
                    if configuration.settings.showShuffleAndRepeat {
                        headerRoundIcon("shuffle")
                    }
                    headerRoundIcon("backward.fill")
                    headerRoundIcon("play.fill")
                    headerRoundIcon("forward.fill")
                    if configuration.settings.showMediaOutputControl {
                        headerRoundIcon("airplayaudio")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, 8)
    }

    private var statsContent: some View {
        let metrics = sampleData.enabledMetrics(settings: configuration.settings)
        return VStack(spacing: 9) {
            if metrics.isEmpty {
                emptyModule(symbol: "chart.xyaxis.line", title: "No graphs enabled")
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: metrics.count <= 3 ? metrics.count : 3), spacing: 8) {
                    ForEach(metrics) { metric in
                        AtollIslandMetricCard(metric: metric)
                    }
                }
            }
        }
        .padding(.top, 8)
    }

    private var timerContent: some View {
        HStack(alignment: .center, spacing: 14) {
            timerRing(size: 72, lineWidth: 7, progress: sampleData.timer.progress, color: configuration.settings.timerSolidColor.swiftUIColor)

            VStack(alignment: .leading, spacing: 8) {
                Text(sampleData.timer.title)
                    .font(.system(size: 18, weight: .semibold))
                    .lineLimit(1)
                if configuration.settings.timerShowsCountdown {
                    Text(sampleData.timer.remaining)
                        .font(.system(size: 26, weight: .bold, design: .monospaced))
                }
                if configuration.settings.timerShowsLabel {
                    statusChip(configuration.settings.timerDisplayMode.capitalized)
                }
                if configuration.settings.timerShowsProgress && configuration.settings.timerProgressStyle != "Ring" {
                    tinyProgress(value: sampleData.timer.progress, color: configuration.settings.timerSolidColor.swiftUIColor)
                        .frame(height: 6)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 10)
    }

    private var clipboardContent: some View {
        listContent(symbol: "doc.on.clipboard", title: "Clipboard", rows: sampleData.clipboard.prefix(configuration.settings.clipboardHistorySize).map { $0 })
    }

    private var colorPickerContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                moduleTitle(symbol: "eyedropper", title: "Recent Colors")
                Spacer()
                if configuration.settings.showColorFormats {
                    Text("HEX RGB HSL")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }

            HStack(spacing: 9) {
                ForEach(Array(sampleData.colors.prefix(configuration.settings.colorHistorySize).enumerated()), id: \.offset) { _, color in
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(color.swiftUIColor)
                        .frame(width: 34, height: 50)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.top, 10)
    }

    private var calendarContent: some View {
        let rows = sampleData.calendar.map { "\($0.time)  \($0.title)" }
        return listContent(symbol: "calendar", title: "Today", rows: configuration.settings.hideCompletedReminders ? Array(rows.prefix(2)) : rows)
    }

    private var shelfContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            moduleTitle(symbol: "tray.fill", title: "Shelf")
            HStack(spacing: 10) {
                ForEach(sampleData.shelfItems) { item in
                    VStack(spacing: 7) {
                        FunctionalIconView(systemSymbolName: item.symbol)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.86))
                        Text(item.title)
                            .font(.system(size: 10, weight: .medium))
                            .lineLimit(1)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            statusChip(configuration.settings.copyOnDrag ? "Copy on drag" : "Move on drag")
        }
        .padding(.top, 10)
    }

    private var privacyContent: some View {
        liveActivityContent(
            symbol: "web.camera",
            title: "Privacy",
            subtitle: "Camera and microphone active",
            tint: .green,
            chips: configuration.settings.enableCapsLockIndicator ? ["Camera", "Mic", "Caps"] : ["Camera", "Mic"]
        )
    }

    private var recordingContent: some View {
        liveActivityContent(
            symbol: "record.circle.fill",
            title: "Recording",
            subtitle: "Screen recording indicator",
            tint: .red,
            chips: ["REC", "Hidden"]
        )
    }

    private var focusContent: some View {
        liveActivityContent(
            symbol: "moon.fill",
            title: "Deep Work",
            subtitle: configuration.settings.focusIndicatorNonPersistent ? "Brief Focus toast" : "Persistent Focus indicator",
            tint: .indigo,
            chips: configuration.settings.showDoNotDisturbLabel ? ["Focus", "DND"] : ["DND"]
        )
    }

    private var batteryContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            moduleTitle(symbol: "battery.75percent", title: "Battery")
            HStack(alignment: .center, spacing: 14) {
                FunctionalIconView(systemSymbolName: "battery.75percent")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 7) {
                    Text(configuration.settings.showBatteryPercentage ? "76%" : "Charging")
                        .font(.system(size: 24, weight: .bold, design: .monospaced))
                    tinyProgress(value: 0.76, color: .green)
                        .frame(height: 7)
                    HStack(spacing: 8) {
                        if configuration.settings.showPowerStatusIcons {
                            statusChip("Plugged in")
                        }
                        statusChip(configuration.settings.lowBatteryHUDStyle.capitalized)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.top, 10)
    }

    private var bluetoothContent: some View {
        liveActivityContent(
            symbol: configuration.settings.useCircularBluetoothBatteryIndicator ? "circle.circle" : "headphones",
            title: "AirPods Pro",
            subtitle: configuration.settings.showBluetoothBatteryPercentageText ? "Left 82% / Right 79%" : "Connected",
            tint: .blue,
            chips: ["Audio", "Battery"]
        )
    }

    private var downloadsContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            moduleTitle(symbol: "arrow.down.circle.fill", title: "Download")
            HStack(spacing: 14) {
                FunctionalIconView(systemSymbolName: "arrow.down.circle.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 8) {
                    Text("ClaudeStats.dmg")
                        .font(.system(size: 16, weight: .semibold))
                    tinyProgress(value: 0.58, color: .accentColor)
                        .frame(height: 8)
                    statusChip(configuration.settings.selectedDownloadIndicatorStyle)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.top, 10)
    }

    private var osdContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            moduleTitle(symbol: "speaker.wave.2.fill", title: "System HUD")
            if configuration.settings.enableVerticalHUD {
                HStack(spacing: 12) {
                    verticalHUD
                    osdSummary
                }
            } else if configuration.settings.enableCircularHUD {
                HStack(spacing: 12) {
                    circularHUD
                    osdSummary
                }
            } else {
                HStack(spacing: 12) {
                    FunctionalIconView(systemSymbolName: "speaker.wave.2.fill")
                        .font(.system(size: 22, weight: .semibold))
                    tinyProgress(value: 0.64, color: configuration.settings.systemEventIndicatorUseAccent ? .accentColor : .white.opacity(0.82))
                        .frame(height: 8)
                    if configuration.settings.showProgressPercentages {
                        Text("64%")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                    }
                }
                .padding(14)
                .background(Color.white.opacity(configuration.settings.enableCustomOSD ? 0.14 : 0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .padding(.top, 10)
    }

    private var lockScreenContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            moduleTitle(symbol: "lock.display", title: "Lock Widgets")
            HStack(spacing: 10) {
                lockWidget(title: "Weather", value: configuration.settings.lockScreenWeatherTemperatureUnit == "Fahrenheit" ? "72F" : "22C", symbol: "cloud.sun.fill", tint: .yellow)
                lockWidget(title: "Battery", value: configuration.settings.lockScreenBatteryShowsBatteryGauge ? "76%" : "On", symbol: "battery.75percent", tint: .green)
                lockWidget(title: "Timer", value: sampleData.timer.remaining, symbol: "timer", tint: configuration.settings.timerSolidColor.swiftUIColor)
            }
        }
        .padding(.top, 10)
    }

    private var extensionContent: some View {
        liveActivityContent(
            symbol: "puzzlepiece.extension",
            title: "Extensions",
            subtitle: "\(configuration.settings.extensionLiveActivityCapacity) live activities available",
            tint: .purple,
            chips: ["Tabs", "Widgets", "Files"]
        )
    }

    private var screenAssistantContent: some View {
        liveActivityContent(
            symbol: "sparkles",
            title: "Screen Assistant",
            subtitle: "\(configuration.settings.selectedAIProvider) in \(configuration.settings.screenAssistantDisplayMode)",
            tint: .yellow,
            chips: ["Capture", "Ask", "Local"]
        )
    }

    private var terminalContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                FunctionalIconView(systemSymbolName: "apple.terminal")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.56))
                Text(configuration.settings.terminalShellPath)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)
                Spacer()
                Text("\(Int(configuration.settings.terminalFontSize)) pt")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)

            VStack(alignment: .leading, spacing: 5) {
                ForEach(sampleData.terminalLines, id: \.self) { line in
                    Text(line)
                        .font(.system(size: max(9, configuration.settings.terminalFontSize - 1), design: .monospaced))
                        .foregroundStyle(line.hasPrefix("$") ? configuration.settings.terminalForegroundColor.swiftUIColor : .green)
                        .lineLimit(1)
                }
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(configuration.settings.terminalCursorColor.swiftUIColor)
                        .frame(width: 7, height: 13)
                    Spacer()
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(configuration.settings.terminalBackgroundColor.swiftUIColor.opacity(configuration.settings.terminalOpacity))
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.top, 8)
    }

    private var headerTabs: [AtollIslandPreviewHeaderTab] {
        var tabs: [AtollIslandPreviewHeaderTab] = []
        tabs.append(.init(id: "home", symbol: "house.fill", title: "Home", isSelected: selectedHeaderID == "home", accent: .white))

        if configuration.enabledTabs.contains(.shelf) || configuration.selectedTab == .shelf {
            tabs.append(.init(id: "shelf", symbol: "tray.fill", title: "Shelf", isSelected: selectedHeaderID == "shelf", accent: .white))
        }
        if configuration.enabledTabs.contains(.timer) || configuration.selectedTab == .timer {
            tabs.append(.init(id: "timer", symbol: "timer", title: "Timer", isSelected: selectedHeaderID == "timer", accent: .white))
        }
        if configuration.enabledTabs.contains(.stats) || configuration.selectedTab == .stats {
            tabs.append(.init(id: "stats", symbol: "chart.xyaxis.line", title: "Stats", isSelected: selectedHeaderID == "stats", accent: .white))
        }
        if configuration.enabledTabs.contains(.clipboard) || configuration.selectedTab == .clipboard {
            tabs.append(.init(id: "clipboard", symbol: "doc.on.clipboard", title: "Clipboard", isSelected: selectedHeaderID == "clipboard", accent: .white))
        }
        if configuration.enabledTabs.contains(.terminal) || configuration.selectedTab == .terminal {
            tabs.append(.init(id: "terminal", symbol: "apple.terminal", title: "Terminal", isSelected: selectedHeaderID == "terminal", accent: .white))
        }
        if configuration.enabledTabs.contains(.extensionBridge) || configuration.selectedTab == .extensionBridge {
            tabs.append(.init(id: "extensions", symbol: "puzzlepiece.extension", title: "Extensions", isSelected: selectedHeaderID == "extensions", accent: .purple, usesAccentBackground: true))
        }

        return Array(tabs.prefix(7))
    }

    private var selectedHeaderID: String {
        switch configuration.selectedTab {
        case .shelf:
            return "shelf"
        case .timer:
            return "timer"
        case .stats:
            return "stats"
        case .clipboard:
            return "clipboard"
        case .terminal:
            return "terminal"
        case .extensionBridge:
            return "extensions"
        default:
            return "home"
        }
    }

    private func moduleTitle(symbol: String, title: String) -> some View {
        HStack(spacing: 8) {
            FunctionalIconView(systemSymbolName: symbol)
                .font(.system(size: 14, weight: .semibold))
            Text(title)
                .font(.system(size: 15, weight: .semibold))
        }
        .foregroundStyle(.white.opacity(0.9))
    }

    private func listContent(symbol: String, title: String, rows: [String]) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            moduleTitle(symbol: symbol, title: title)
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.accentColor.opacity(0.85))
                        .frame(width: 5, height: 5)
                    Text(row)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 3)
            }
        }
        .padding(.top, 10)
    }

    private func liveActivityContent(symbol: String, title: String, subtitle: String, tint: Color, chips: [String]) -> some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(tint.opacity(0.18))
                FunctionalIconView(systemSymbolName: symbol)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: 74, height: 74)

            VStack(alignment: .leading, spacing: 9) {
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(2)
                HStack(spacing: 7) {
                    ForEach(chips, id: \.self) { chip in
                        statusChip(chip)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 10)
    }

    private func emptyModule(symbol: String, title: String) -> some View {
        VStack(spacing: 9) {
            FunctionalIconView(systemSymbolName: symbol)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.white.opacity(0.38))
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.56))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var verticalHUD: some View {
        VStack(spacing: 8) {
            FunctionalIconView(systemSymbolName: "speaker.wave.2.fill")
                .font(.system(size: 15, weight: .semibold))
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.12))
                .frame(width: 18, height: 72)
                .overlay(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.accentColor)
                        .frame(height: 46)
                }
            if configuration.settings.showProgressPercentages {
                Text("64")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var circularHUD: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: 8)
            Circle()
                .trim(from: 0, to: 0.64)
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
            FunctionalIconView(systemSymbolName: "speaker.wave.2.fill")
                .font(.system(size: 16, weight: .semibold))
        }
        .frame(width: 82, height: 82)
    }

    private var osdSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(configuration.settings.enableCustomOSD ? "Custom OSD" : "System OSD")
                .font(.system(size: 17, weight: .semibold))
            Text(configuration.settings.showProgressPercentages ? "64%" : "Volume")
                .font(.system(size: 22, weight: .bold, design: .monospaced))
            statusChip(configuration.settings.systemEventIndicatorUseAccent ? "Accent" : "Monochrome")
        }
    }

    private func lockWidget(title: String, value: String, symbol: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            FunctionalIconView(systemSymbolName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tint)
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var headerBattery: some View {
        HStack(spacing: 3) {
            if configuration.settings.showBatteryPercentage {
                Text("76")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))
            }
            FunctionalIconView(systemSymbolName: "battery.75percent")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.green)
        }
        .frame(height: 30)
    }

    private var openWidth: CGFloat {
        configuration.sizePreset.openDisplayWidth
    }

    private var openHeight: CGFloat {
        configuration.sizePreset.openDisplayHeight
    }
}

private struct AtollIslandPreviewHeaderTab: Identifiable {
    let id: String
    let symbol: String
    let title: String
    let isSelected: Bool
    let accent: Color
    var usesAccentBackground = false
}

private struct AtollIslandPreviewHeaderTabView: View {
    let tab: AtollIslandPreviewHeaderTab

    var body: some View {
        FunctionalIconView(systemSymbolName: tab.symbol)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(tab.isSelected ? tab.accent : .gray)
            .frame(width: 26, height: 26)
            .background {
                if tab.isSelected {
                    Capsule()
                        .fill((tab.usesAccentBackground ? tab.accent : Color(nsColor: .secondarySystemFill)).opacity(0.25))
                        .shadow(color: tab.accent.opacity(0.35), radius: 8)
                }
            }
            .help(tab.title)
    }
}

private struct AtollIslandMetricCard: View {
    let metric: AtollIslandPreviewSampleData.Metric

    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: 4) {
                FunctionalIconView(systemSymbolName: metric.symbol)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(metric.color.swiftUIColor)
                Text(metric.title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(metric.value)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
            }
            AtollIslandMiniGraph(data: metric.data, color: metric.color.swiftUIColor)
                .frame(height: 28)
        }
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: 74)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.08))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
                }
        )
    }
}

private struct AtollIslandMiniGraph: View {
    let data: [Double]
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            let normalized = normalizedData
            Path { path in
                guard normalized.count > 1 else { return }
                let stepX = geometry.size.width / CGFloat(normalized.count - 1)
                for index in normalized.indices {
                    let x = CGFloat(index) * stepX
                    let y = geometry.size.height * (1 - CGFloat(normalized[index]))
                    if index == normalized.startIndex {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
    }

    private var normalizedData: [Double] {
        let maxValue = max(data.max() ?? 1, 0.001)
        return data.map { min(max($0 / maxValue, 0), 1) }
    }
}

private struct AtollIslandPreviewShell<Content: View>: View {
    let isDynamicIsland: Bool
    let isOpen: Bool
    let enableShadow: Bool
    let content: Content

    init(
        isDynamicIsland: Bool,
        isOpen: Bool,
        enableShadow: Bool,
        @ViewBuilder content: () -> Content
    ) {
        self.isDynamicIsland = isDynamicIsland
        self.isOpen = isOpen
        self.enableShadow = enableShadow
        self.content = content()
    }

    var body: some View {
        Group {
            if isDynamicIsland {
                content
                    .background(Color.black)
                    .clipShape(DynamicIslandPillShape(cornerRadius: isOpen ? dynamicIslandPillCornerRadiusInsets.opened : dynamicIslandPillCornerRadiusInsets.closed.standard))
            } else {
                content
                    .background(Color.black)
                    .clipShape(NotchShape(topCornerRadius: cornerRadii.top, bottomCornerRadius: cornerRadii.bottom))
            }
        }
        .shadow(color: enableShadow ? Color.black.opacity(0.42) : .clear, radius: enableShadow ? 10 : 0, y: 4)
    }

    private var cornerRadii: (top: CGFloat, bottom: CGFloat) {
        if isOpen {
            return cornerRadiusInsets.opened
        }
        return cornerRadiusInsets.closed
    }
}

private func previewLabel(_ text: String) -> some View {
    Text(text.uppercased())
        .font(.system(size: 9, weight: .bold, design: .rounded))
        .tracking(0.8)
        .foregroundStyle(Color.secondary)
}

private enum AtollIslandPreviewChipStyle {
    case darkSurface
    case ambient
}

private func statusChip(_ text: String, style: AtollIslandPreviewChipStyle = .darkSurface) -> some View {
    AtollIslandPreviewStatusChip(text: text, style: style)
}

private struct AtollIslandPreviewStatusChip: View {
    @Environment(\.colorScheme) private var colorScheme

    let text: String
    let style: AtollIslandPreviewChipStyle

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(foregroundStyle)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(backgroundStyle, in: Capsule())
            .overlay {
                if style == .ambient {
                    Capsule()
                        .stroke(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.10), lineWidth: 1)
                }
            }
    }

    private var foregroundStyle: Color {
        switch style {
        case .darkSurface:
            return .white.opacity(0.78)
        case .ambient:
            return .primary.opacity(0.82)
        }
    }

    private var backgroundStyle: Color {
        switch style {
        case .darkSurface:
            return .white.opacity(0.10)
        case .ambient:
            return Color(nsColor: .controlBackgroundColor).opacity(colorScheme == .dark ? 0.62 : 0.92)
        }
    }
}

private func supplementLine(_ title: String, detail: String) -> some View {
    VStack(alignment: .leading, spacing: 3) {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.primary.opacity(0.82))
            .lineLimit(1)
        Text(detail)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Color.secondary)
            .lineLimit(1)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
}

private func artwork(size: CGFloat, colors: [AtollSettingColor]) -> some View {
    RoundedRectangle(cornerRadius: max(6, size * 0.18), style: .continuous)
        .fill(
            LinearGradient(
                colors: colors.map(\.swiftUIColor),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .frame(width: size, height: size)
        .overlay {
            FunctionalIconView(systemSymbolName: "music.note")
                .font(.system(size: size * 0.32, weight: .semibold))
                .foregroundStyle(.white.opacity(0.88))
        }
}

private func timerRing(size: CGFloat, lineWidth: CGFloat, progress: Double, color: Color) -> some View {
    ZStack {
        Circle()
            .stroke(Color.white.opacity(0.15), lineWidth: lineWidth)
        Circle()
            .trim(from: 0, to: min(max(progress, 0), 1))
            .stroke(
                color,
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            )
            .rotationEffect(.degrees(-90))
        FunctionalIconView(systemSymbolName: "timer")
            .font(.system(size: max(10, size * 0.25), weight: .semibold))
            .foregroundStyle(.white.opacity(0.86))
    }
    .frame(width: size, height: size)
}

private func tinyProgress(value: Double, color: Color) -> some View {
    GeometryReader { geometry in
        RoundedRectangle(cornerRadius: geometry.size.height / 2, style: .continuous)
            .fill(Color.white.opacity(0.14))
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: geometry.size.height / 2, style: .continuous)
                    .fill(color)
                    .frame(width: max(geometry.size.width * CGFloat(min(max(value, 0), 1)), geometry.size.height))
            }
    }
}

private func waveform(color: Color) -> some View {
    HStack(alignment: .center, spacing: 2) {
        ForEach([0.35, 0.72, 0.48, 0.92, 0.58, 0.78, 0.42], id: \.self) { height in
            Capsule()
                .fill(color.opacity(0.9))
                .frame(width: 3, height: 18 * height)
        }
    }
}

private func headerRoundIcon(_ symbol: String) -> some View {
    FunctionalIconView(systemSymbolName: symbol)
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.white.opacity(0.86))
        .frame(width: 28, height: 28)
        .background(Color.black, in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
        }
}

private extension AtollIslandPreviewSettings {
    var usesDynamicIslandShape: Bool {
        externalDisplayStyle == "Dynamic Island"
    }
}

private extension AtollSettingColor {
    var swiftUIColor: Color {
        Color(red: red, green: green, blue: blue, opacity: opacity)
    }
}

private extension AtollIslandPreviewSampleData {
    func enabledMetrics(settings: AtollIslandPreviewSettings) -> [Metric] {
        stats.filter { metric in
            switch metric.id {
            case "cpu":
                return settings.showCpuGraph
            case "memory":
                return settings.showMemoryGraph
            case "gpu":
                return settings.showGpuGraph
            case "network":
                return settings.showNetworkGraph
            case "disk":
                return settings.showDiskGraph
            default:
                return true
            }
        }
    }
}
