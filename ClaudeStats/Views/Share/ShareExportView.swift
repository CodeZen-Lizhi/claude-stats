import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// The "Share Stats" window: a live preview of the exported panel on the left,
/// the export options (appearance, pane, time range / activity range, chart) on
/// the right, and Save / Copy actions that rasterise the panel to a PNG via
/// `ImageRenderer`.
struct ShareExportView: View {
    static let windowID = "share-export"

    @Environment(AppEnvironment.self) private var env

    @State private var scheme: ColorScheme = .light
    @State private var showTopBar = true
    @State private var stampPrecision: ExportStampPrecision = .monthOnly
    @State private var pane: StatsPane = .usage
    @State private var preset: StatsPeriod = .today
    @State private var useCustomRange = false
    @State private var customStart = Calendar.current.date(byAdding: .day, value: -6, to: .now) ?? .now
    @State private var customEnd = Date.now
    @State private var chartStyle: TrendChartStyle = .line
    @State private var useLog = false
    @State private var activityVM = AIActivityViewModel()
    @State private var statusMessage: String?

    private var availablePanes: [StatsPane] {
        StatsPane.allCases.filter { pane in
            pane != .git && (pane != .activity || env.preferences.aiActivityAnalysisEnabled)
        }
    }

    private var selection: PeriodSelection {
        useCustomRange ? .custom(start: customStart, end: customEnd) : .preset(preset)
    }

    private var exportConfig: StatsExportConfig {
        StatsExportConfig(
            usage: UsageView.ExportConfig(period: selection, chartStyle: chartStyle, useLog: useLog && chartStyle == .line),
            activity: AIActivityView.ExportData(
                range: activityVM.range,
                selectedDay: activityVM.selectedDay,
                dayActivity: activityVM.dayActivity,
                trend: activityVM.trend,
                permissionDenied: activityVM.permissionState == .needsFullDiskAccess,
                isLoading: activityVM.isLoading
            ),
            showTopBar: showTopBar,
            stampDate: .now,
            stampPrecision: stampPrecision
        )
    }

    private var activityLoading: Bool { pane == .activity && activityVM.isLoading }

    private var activityReloadKey: AnyHashable {
        [AnyHashable(pane == .activity), AnyHashable(activityVM.reloadToken),
         AnyHashable(env.store.lastRefreshedAt), AnyHashable(env.preferences.effectiveIDEBundleIDs),
         AnyHashable(env.preferences.selectedProvider)]
    }

    /// A day binding that re-triggers the activity reload when changed.
    private var dayBinding: Binding<Date> {
        Binding(
            get: { activityVM.selectedDay },
            set: { activityVM.selectedDay = $0; activityVM.bumpReload() }
        )
    }

    /// The panel as it will be exported. Used both for the on-screen preview and
    /// (re-instantiated) as the `ImageRenderer` content.
    private func exportPanel(paneBinding: Binding<StatsPane>) -> some View {
        StatsPanelBody(pane: paneBinding, export: exportConfig)
            .frame(width: 380)
            .fixedSize(horizontal: false, vertical: true)
            .font(.sora(13))
            .tint(.stxAccent)
            .background(Color.stxBackground)
            .environment(\.colorScheme, scheme)
    }

    var body: some View {
        HStack(spacing: 0) {
            FadingScrollView {
                exportPanel(paneBinding: $pane)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator, lineWidth: 1))
                    .padding(20)
            }
            .frame(width: 420)
            .background(scheme == .dark ? Color(white: 0.12) : Color(white: 0.9))

            Divider()

            settings
                .frame(width: 280, alignment: .topLeading)
                .padding(20)
        }
        .frame(minHeight: 540)
        .task(id: activityReloadKey) {
            guard pane == .activity else { return }
            await activityVM.reload(sessions: env.store.sessions(for: env.preferences.selectedProvider), bundleIDs: env.preferences.effectiveIDEBundleIDs)
        }
        .onAppear { activityVM.refreshPermissionState() }
    }

    @ViewBuilder
    private var settings: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("SHARE STATS")
                .font(.sora(15, weight: .semibold))
                .tracking(1.4)

            optionGroup("Appearance") {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Appearance", selection: $scheme) {
                        Text("Light").tag(ColorScheme.light)
                        Text("Dark").tag(ColorScheme.dark)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    Toggle(isOn: $showTopBar) {
                        Text("Show top bar").font(.sora(11))
                    }
                    Text("The platform switcher (or scanline strip) above the title.")
                        .font(.sora(9))
                        .foregroundStyle(.secondary)
                }
            }

            optionGroup("Timestamp") {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Timestamp", selection: $stampPrecision) {
                        ForEach(ExportStampPrecision.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    Text("Today's date in the header corner. Year + month always show; “Day” adds the day, “Time” also adds the hour and minute.")
                        .font(.sora(9))
                        .foregroundStyle(.secondary)
                }
            }

            optionGroup("Pane") {
                Picker("Pane", selection: $pane) {
                    ForEach(availablePanes) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            if pane == .usage {
                optionGroup("Chart") {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("Chart", selection: $chartStyle) {
                            Text("Line").tag(TrendChartStyle.line)
                            Text("Bars").tag(TrendChartStyle.bar)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()

                        Toggle(isOn: $useLog) {
                            Text("ln scale (compress gaps between models)").font(.sora(11))
                        }
                        .disabled(chartStyle == .bar)

                        Text("Bars / ln also applies only to multi-day ranges — Today is always an hourly line.")
                            .font(.sora(9))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if pane == .activity {
                optionGroup("Activity range") {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("Range", selection: $activityVM.range) {
                            ForEach(ActivityRange.allCases) { Text($0.shortLabel).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()

                        if activityVM.range == .day {
                            DatePicker("Day", selection: dayBinding, in: ...activityVM.today, displayedComponents: .date)
                                .font(.sora(11))
                        }
                    }
                }
            } else {
                optionGroup("Time range") {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("Time range", selection: $preset) {
                            ForEach(StatsPeriod.allCases) { Text($0.displayName).tag($0) }
                        }
                        .labelsHidden()
                        .disabled(useCustomRange)

                        DisclosureGroup(isExpanded: $useCustomRange) {
                            VStack(alignment: .leading, spacing: 6) {
                                DatePicker("From", selection: $customStart, displayedComponents: .date)
                                DatePicker("To", selection: $customEnd, displayedComponents: .date)
                            }
                            .font(.sora(11))
                            .padding(.top, 4)
                        } label: {
                            Text("Advanced — custom range").font(.sora(11))
                        }
                    }
                }
            }

            Spacer(minLength: 0)

            if let statusMessage {
                Text(statusMessage)
                    .font(.sora(10))
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Copy") { copyPNG() }
                Spacer()
                Button("Save PNG…") { savePNG() }
                    .keyboardShortcut(.defaultAction)
            }
            .disabled(activityLoading)
        }
    }

    private func optionGroup<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.sora(10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
            content()
        }
    }

    // MARK: - PNG export

    @MainActor
    private func renderPNG() -> (data: Data, image: NSImage)? {
        let renderer = ImageRenderer(content: exportPanel(paneBinding: .constant(pane)).environment(env))
        renderer.scale = 3
        let appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)

        var result: (Data, NSImage)?
        let render = {
            guard let cg = renderer.cgImage else { return }
            let rep = NSBitmapImageRep(cgImage: cg)
            guard let data = rep.representation(using: .png, properties: [:]) else { return }
            let image = NSImage(size: NSSize(width: cg.width, height: cg.height))
            image.addRepresentation(rep)
            result = (data, image)
        }
        if let appearance {
            appearance.performAsCurrentDrawingAppearance(render)
        } else {
            render()
        }
        return result
    }

    private func savePNG() {
        guard let (data, _) = renderPNG() else {
            statusMessage = "Couldn't render the image."
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        panel.nameFieldStringValue = "Claude Stats \(pane.title) \(df.string(from: .now)).png"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url)
            statusMessage = "Saved \(url.lastPathComponent)."
        } catch {
            statusMessage = "Save failed: \(error.localizedDescription)"
        }
    }

    private func copyPNG() {
        guard let (_, image) = renderPNG() else {
            statusMessage = "Couldn't render the image."
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
        statusMessage = "Copied to clipboard."
    }
}

#if DEBUG
#Preview {
    ShareExportView()
        .environment(AppEnvironment.preview())
}
#endif
