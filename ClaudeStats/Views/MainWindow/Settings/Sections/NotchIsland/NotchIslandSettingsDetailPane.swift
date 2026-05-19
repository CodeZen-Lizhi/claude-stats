import AppKit
import AtollEmbed
import SwiftUI

struct NotchIslandSettingsDetailPane: View {
    let tab: NotchIslandSettingsTab
    let preferences: Preferences
    let isFeatureEnabled: Bool
    let refreshToken: Int
    let onSelectSection: (SettingsSection) -> Void
    let onSettingChanged: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                if !isFeatureEnabled {
                    FeatureDisabledNotice(
                        featureName: "Notch Island",
                        message: "Turn it on in Features to edit display behavior and modules."
                    ) {
                        onSelectSection(.features)
                    }
                }

                NotchIslandModulePreview(
                    tab: tab,
                    preferences: preferences,
                    refreshToken: refreshToken
                )
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 18)

            Rectangle()
                .fill(Color.stxStroke)
                .frame(height: 1)

            FadingScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if tab == .island {
                        islandDisplaySettings(prefs: preferences)
                    }

                    if let module = tab.module {
                        moduleAvailabilitySettings(module, prefs: preferences)
                    }

                    ForEach(AtollSettingsBridge.groups(for: tab.bridgeTab)) { group in
                        SettingGroup(title: group.title, caption: group.caption) {
                            VStack(spacing: 0) {
                                ForEach(Array(group.settings.enumerated()), id: \.element.id) { index, descriptor in
                                    AtollSettingControlRow(
                                        descriptor: descriptor,
                                        onSettingChanged: onSettingChanged
                                    )
                                    if index != group.settings.count - 1 {
                                        SettingRowDivider()
                                    }
                                }
                            }
                            .settingCard()
                        }
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 22)
                .padding(.bottom, 28)
            }
            .disabled(!isFeatureEnabled)
            .opacity(isFeatureEnabled ? 1 : 0.58)
        }
    }

    private func islandDisplaySettings(prefs: Preferences) -> some View {
        SettingGroup(title: "Display", caption: "Claude Stats owns placement, sizing, and the global shortcut.") {
            VStack(spacing: 0) {
                SettingRow(title: "Display mode", description: "Where the island window is created.") {
                    Picker("", selection: displayModeBinding(prefs)) {
                        ForEach(NotchIslandDisplayMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 190)
                }

                SettingRowDivider()

                SettingRow(title: "Size", description: "Compact and expanded island dimensions.") {
                    Picker("", selection: sizePresetBinding(prefs)) {
                        ForEach(NotchIslandSizePreset.allCases) { preset in
                            Text(preset.displayName).tag(preset)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 150)
                }

                SettingRowDivider()

                SettingRow(title: "Hover expansion", description: "Expand while the pointer is over the island.") {
                    Toggle("", isOn: hoverExpansionBinding(prefs))
                        .labelsHidden()
                }

                SettingRowDivider()

                SettingRow(title: "Shortcut bridge", description: "Open or close the island with Command-Option-N.") {
                    Toggle("", isOn: shortcutBinding(prefs))
                        .labelsHidden()
                }
            }
            .settingCard()
        }
    }

    private func moduleAvailabilitySettings(_ module: NotchIslandModule, prefs: Preferences) -> some View {
        let descriptor = NotchIslandFeatureRegistry.descriptor(for: module)
        return SettingGroup(title: "Module", caption: "Module availability is stored in Claude Stats; Atoll-specific settings below tune behavior inside the module.") {
            VStack(spacing: 0) {
                SettingRow(title: module.title, description: module.settingsDescription) {
                    HStack(spacing: 10) {
                        Text(descriptor.statusText)
                            .font(.sora(10, weight: .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .foregroundStyle(module.isHeavyOrExperimental ? Color.stxMuted : Color.primary)

                        Toggle("", isOn: moduleBinding(module, prefs: prefs))
                            .labelsHidden()
                    }
                    .frame(width: 210, alignment: .trailing)
                }
            }
            .settingCard()
        }
    }

    private func moduleBinding(_ module: NotchIslandModule, prefs: Preferences) -> Binding<Bool> {
        Binding(
            get: { prefs.notchIslandEnabledModules.contains(module) },
            set: { isEnabled in
                var modules = prefs.notchIslandEnabledModules
                if isEnabled {
                    modules.insert(module)
                } else {
                    modules.remove(module)
                }
                prefs.notchIslandEnabledModules = modules
                onSettingChanged()
            }
        )
    }

    private func displayModeBinding(_ prefs: Preferences) -> Binding<NotchIslandDisplayMode> {
        Binding(
            get: { prefs.notchIslandDisplayMode },
            set: {
                prefs.notchIslandDisplayMode = $0
                onSettingChanged()
            }
        )
    }

    private func sizePresetBinding(_ prefs: Preferences) -> Binding<NotchIslandSizePreset> {
        Binding(
            get: { prefs.notchIslandSizePreset },
            set: {
                prefs.notchIslandSizePreset = $0
                onSettingChanged()
            }
        )
    }

    private func hoverExpansionBinding(_ prefs: Preferences) -> Binding<Bool> {
        Binding(
            get: { prefs.notchIslandHoverExpansionEnabled },
            set: {
                prefs.notchIslandHoverExpansionEnabled = $0
                onSettingChanged()
            }
        )
    }

    private func shortcutBinding(_ prefs: Preferences) -> Binding<Bool> {
        Binding(
            get: { prefs.notchIslandShortcutEnabled },
            set: {
                prefs.notchIslandShortcutEnabled = $0
                onSettingChanged()
            }
        )
    }
}

private struct AtollSettingControlRow: View {
    let descriptor: AtollSettingDescriptor
    let onSettingChanged: () -> Void

    var body: some View {
        SettingRow(title: descriptor.title, description: descriptor.description) {
            accessory
        }
    }

    @ViewBuilder
    private var accessory: some View {
        switch descriptor.control {
        case .toggle:
            Toggle("", isOn: boolBinding)
                .labelsHidden()
        case .slider(let min, let max, let step, let unit):
            VStack(alignment: .trailing, spacing: 7) {
                Text(sliderDisplay(unit: unit, max: max))
                    .font(.sora(10, weight: .medium).monospacedDigit())
                    .foregroundStyle(Color.stxMuted)
                Slider(value: numericBinding, in: min...max, step: step)
                    .frame(width: 210)
            }
        case .picker(let options):
            Picker("", selection: stringBinding) {
                ForEach(options) { option in
                    Text(option.title).tag(option.value)
                }
            }
            .labelsHidden()
            .frame(width: 210)
        case .text:
            TextField("", text: stringBinding)
                .textFieldStyle(.roundedBorder)
                .frame(width: 210)
        case .color:
            ColorPicker("", selection: colorBinding, supportsOpacity: true)
                .labelsHidden()
                .frame(width: 80)
        }
    }

    private var boolBinding: Binding<Bool> {
        Binding(
            get: {
                guard case .bool(let value) = AtollSettingsBridge.value(for: descriptor.id) else { return false }
                return value
            },
            set: { newValue in
                if AtollSettingsBridge.setValue(.bool(newValue), for: descriptor.id) {
                    onSettingChanged()
                }
            }
        )
    }

    private var numericBinding: Binding<Double> {
        Binding(
            get: { numericValue },
            set: { newValue in
                let current = AtollSettingsBridge.value(for: descriptor.id)
                let value: AtollSettingValue
                if case .int = current {
                    value = .int(Int(newValue.rounded()))
                } else {
                    value = .double(newValue)
                }
                if AtollSettingsBridge.setValue(value, for: descriptor.id) {
                    onSettingChanged()
                }
            }
        )
    }

    private var stringBinding: Binding<String> {
        Binding(
            get: { stringValue },
            set: { newValue in
                let current = AtollSettingsBridge.value(for: descriptor.id)
                let value: AtollSettingValue
                if case .int = current, let intValue = Int(newValue) {
                    value = .int(intValue)
                } else {
                    value = .string(newValue)
                }
                if AtollSettingsBridge.setValue(value, for: descriptor.id) {
                    onSettingChanged()
                }
            }
        )
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: {
                guard case .color(let color) = AtollSettingsBridge.value(for: descriptor.id) else {
                    return .accentColor
                }
                return color.swiftUIColor
            },
            set: { newValue in
                if AtollSettingsBridge.setValue(.color(AtollSettingColor(newValue)), for: descriptor.id) {
                    onSettingChanged()
                }
            }
        )
    }

    private var numericValue: Double {
        switch AtollSettingsBridge.value(for: descriptor.id) {
        case .double(let value): value
        case .int(let value): Double(value)
        default: 0
        }
    }

    private var stringValue: String {
        switch AtollSettingsBridge.value(for: descriptor.id) {
        case .string(let value): value
        case .int(let value): String(value)
        case .double(let value): String(Int(value.rounded()))
        default: ""
        }
    }

    private func sliderDisplay(unit: String?, max: Double) -> String {
        let value = numericValue
        if let unit {
            if unit == "%" {
                return "\(Int(value.rounded()))\(unit)"
            }
            return "\(trimmed(value)) \(unit)"
        }
        if max <= 1 {
            return "\(Int((value * 100).rounded()))%"
        }
        return trimmed(value)
    }

    private func trimmed(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(format: "%.2f", value)
    }
}

private extension AtollSettingColor {
    init(_ color: Color) {
        let nsColor = NSColor(color)
        let resolved = nsColor.usingColorSpace(.sRGB) ?? nsColor
        self.init(
            red: Double(resolved.redComponent),
            green: Double(resolved.greenComponent),
            blue: Double(resolved.blueComponent),
            opacity: Double(resolved.alphaComponent)
        )
    }

    var swiftUIColor: Color {
        Color(red: red, green: green, blue: blue, opacity: opacity)
    }
}
