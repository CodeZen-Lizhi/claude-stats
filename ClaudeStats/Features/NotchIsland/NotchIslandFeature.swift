import Foundation

struct NotchIslandFeatureDescriptor: Identifiable, Sendable {
    var module: NotchIslandModule
    var permissionState: NotchIslandPermissionState
    var isNativePortReady: Bool
    var sourcePath: String

    var id: NotchIslandModule { module }

    var statusText: String {
        if isNativePortReady {
            return permissionState.displayName
        }
        return "\(permissionState.displayName) - Atoll source linked"
    }
}

enum NotchIslandFeatureRegistry {
    static let all: [NotchIslandFeatureDescriptor] = NotchIslandModule.allCases.map { module in
        NotchIslandFeatureDescriptor(
            module: module,
            permissionState: permissionState(for: module),
            isNativePortReady: nativePortReadyModules.contains(module),
            sourcePath: module.atollSourceHint
        )
    }

    static func descriptor(for module: NotchIslandModule) -> NotchIslandFeatureDescriptor {
        all.first { $0.module == module } ?? NotchIslandFeatureDescriptor(
            module: module,
            permissionState: .sourceLinked,
            isNativePortReady: false,
            sourcePath: module.atollSourceHint
        )
    }

    private static let nativePortReadyModules: Set<NotchIslandModule> = [
        .stats,
        .timer,
        .clipboard,
        .colorPicker,
        .battery,
        .privacy,
        .terminal
    ]

    private static func permissionState(for module: NotchIslandModule) -> NotchIslandPermissionState {
        switch module {
        case .media:
            .needsPermission("Music / Apple Events")
        case .calendar:
            .needsPermission("Calendar")
        case .colorPicker, .clipboard, .stats, .timer, .battery, .terminal:
            .available
        case .privacy:
            .needsPermission("Camera / Microphone")
        case .recording, .screenAssistant:
            .needsPermission("Screen Recording")
        case .shelf, .focus, .bluetooth, .downloads, .osd, .lockScreenWidgets, .extensionBridge:
            .disabledByDefault
        }
    }
}
