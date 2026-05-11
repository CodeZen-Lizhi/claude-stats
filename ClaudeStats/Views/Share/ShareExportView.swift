import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// The "Share Stats" window: a live preview of the exported panel on the left,
/// the export options (appearance, pane, time range) on the right, and Save /
/// Copy actions that rasterise the panel to a PNG via `ImageRenderer`.
struct ShareExportView: View {
    static let windowID = "share-export"

    @Environment(AppEnvironment.self) private var env

    @State private var scheme: ColorScheme = .light
    @State private var pane: StatsPane = .usage
    @State private var preset: StatsPeriod = .today
    @State private var useCustomRange = false
    @State private var customStart = Calendar.current.date(byAdding: .day, value: -6, to: .now) ?? .now
    @State private var customEnd = Date.now
    @State private var chartStyle: TrendChartStyle = .line
    @State private var useLog = false
    @State private var statusMessage: String?

    private var selection: PeriodSelection {
        useCustomRange ? .custom(start: customStart, end: customEnd) : .preset(preset)
    }

    private var exportConfig: UsageView.ExportConfig {
        UsageView.ExportConfig(period: selection, chartStyle: chartStyle, useLog: useLog && chartStyle == .line)
    }

    /// The panel as it will be exported. Used both for the on-screen preview and
    /// (re-instantiated) as the `ImageRenderer` content.
    private func exportPanel(paneBinding: Binding<StatsPane>) -> some View {
        StatsPanelBody(pane: paneBinding, exportConfig: exportConfig)
            .frame(width: 380)
            .fixedSize(horizontal: false, vertical: true)
            .font(.sora(13))
            .tint(.stxAccent)
            .background(Color.stxBackground)
            .environment(\.colorScheme, scheme)
    }

    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
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
    }

    @ViewBuilder
    private var settings: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("SHARE STATS")
                .font(.sora(15, weight: .semibold))
                .tracking(1.4)

            optionGroup("Appearance") {
                Picker("Appearance", selection: $scheme) {
                    Text("Light").tag(ColorScheme.light)
                    Text("Dark").tag(ColorScheme.dark)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            optionGroup("Pane") {
                Picker("Pane", selection: $pane) {
                    ForEach(StatsPane.allCases) { Text($0.title).tag($0) }
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
        panel.nameFieldStringValue = "Claude Stats \(df.string(from: .now)).png"
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
