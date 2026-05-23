import Darwin
import CoreGraphics
import Foundation
import OpenComputerUseKit

@MainActor
protocol ComputerUseAutomating: AnyObject {
    func getAppSnapshot(app: String, policy: ComputerUseAutomationPolicy) throws -> ComputerUseAutomationSnapshot
    func getAppState(app: String, policy: ComputerUseAutomationPolicy) throws -> String
    func click(app: String, elementIndex: String, policy: ComputerUseAutomationPolicy) throws -> String
    func click(
        app: String,
        x: Double,
        y: Double,
        policy: ComputerUseAutomationPolicy,
        allowsForegroundPointerFallback: Bool
    ) throws -> String
    func pressKey(app: String, key: String, policy: ComputerUseAutomationPolicy) throws -> String
    func typeText(app: String, text: String, policy: ComputerUseAutomationPolicy) throws -> String
    func setValue(app: String, elementIndex: String, value: String, policy: ComputerUseAutomationPolicy) throws -> String
}

enum ComputerUseAutomationPolicy: Sendable, Equatable {
    case readOnly
    case userInitiatedControl

    var allowsActions: Bool {
        self == .userInitiatedControl
    }
}

enum ComputerUseAutomationError: LocalizedError, Equatable, Sendable {
    case appNotAllowed(String)
    case actionNotAllowed
    case foregroundPointerFallbackNotAllowed(String)
    case emptyResult
    case toolFailed(String)

    var errorDescription: String? {
        switch self {
        case .appNotAllowed(let app):
            "Computer Use automation is not allowed for \(app)."
        case .actionNotAllowed:
            "Computer Use actions are not allowed for this capture policy."
        case .foregroundPointerFallbackNotAllowed(let app):
            "Foreground pointer fallback is not allowed for \(app)."
        case .emptyResult:
            "Computer Use returned no readable app state."
        case .toolFailed(let message):
            message
        }
    }

    var isAccessibilityPermissionFailure: Bool {
        guard case .toolFailed(let message) = self else { return false }
        return message.localizedCaseInsensitiveContains("accessibility permission")
            || message.localizedCaseInsensitiveContains("access app interfaces")
    }
}

struct ComputerUseAutomationSnapshot: Sendable, Equatable {
    let text: String
    let windowSize: CGSize?
    let screenshotPixelSize: CGSize?
    let elements: [ComputerUseAutomationElement]

    var hasScreenshotScale: Bool {
        guard let windowSize, let screenshotPixelSize else { return false }
        return windowSize.width > 0
            && windowSize.height > 0
            && screenshotPixelSize.width > 0
            && screenshotPixelSize.height > 0
    }

    func screenshotPoint(forWindowPoint point: CGPoint) -> CGPoint {
        guard hasScreenshotScale, let windowSize, let screenshotPixelSize else {
            return point
        }

        return CGPoint(
            x: point.x * screenshotPixelSize.width / windowSize.width,
            y: point.y * screenshotPixelSize.height / windowSize.height
        )
    }
}

struct ComputerUseAutomationElement: Sendable, Equatable {
    let index: String
    let role: String
    let label: String
    let actions: [String]
    let frame: CGRect?
    let isSyntheticText: Bool
}

@MainActor
protocol ComputerUseAutomationBackend: AnyObject {
    func getAppSnapshot(app: String) throws -> ComputerUseAutomationSnapshot
    func getAppState(app: String) throws -> String
    func click(app: String, elementIndex: String) throws -> String
    func click(app: String, x: Double, y: Double) throws -> String
    func pressKey(app: String, key: String) throws -> String
    func typeText(app: String, text: String) throws -> String
    func setValue(app: String, elementIndex: String, value: String) throws -> String
}

@MainActor
final class OpenComputerUseAutomationBackend: ComputerUseAutomationBackend {
    private let service: ComputerUseService

    init(snapshotConfiguration: ComputerUseSnapshotConfiguration) {
        self.service = ComputerUseService(snapshotConfiguration: snapshotConfiguration)
    }

    func getAppSnapshot(app: String) throws -> ComputerUseAutomationSnapshot {
        ComputerUseAutomationSnapshot(openSnapshot: try service.appSnapshot(app: app))
    }

    func getAppState(app: String) throws -> String {
        try primaryText(from: service.getAppState(app: app))
    }

    func click(app: String, elementIndex: String) throws -> String {
        try primaryText(from: service.click(
            app: app,
            elementIndex: elementIndex,
            x: nil,
            y: nil,
            clickCount: 1,
            mouseButton: "left"
        ))
    }

    func click(app: String, x: Double, y: Double) throws -> String {
        try primaryText(from: service.click(
            app: app,
            elementIndex: nil,
            x: x,
            y: y,
            clickCount: 1,
            mouseButton: "left"
        ))
    }

    func pressKey(app: String, key: String) throws -> String {
        try primaryText(from: service.pressKey(app: app, key: key))
    }

    func typeText(app: String, text: String) throws -> String {
        try primaryText(from: service.typeText(app: app, text: text))
    }

    func setValue(app: String, elementIndex: String, value: String) throws -> String {
        try primaryText(from: service.setValue(app: app, elementIndex: elementIndex, value: value))
    }

    private func primaryText(from result: ToolCallResult) throws -> String {
        guard !result.isError else {
            throw ComputerUseAutomationError.toolFailed(result.primaryText ?? "Computer Use tool failed.")
        }
        guard let text = result.primaryText, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ComputerUseAutomationError.emptyResult
        }
        return text
    }
}

@MainActor
final class ComputerUseAutomationService: ComputerUseAutomating {
    private static let globalPointerFallbackEnvironmentKey = "OPEN_COMPUTER_USE_ALLOW_GLOBAL_POINTER_FALLBACKS"

    private let allowedApps: Set<String>
    private let readOnlyBackend: any ComputerUseAutomationBackend
    private let controlBackend: any ComputerUseAutomationBackend

    init(
        allowedApps: Set<String> = [ClaudeDesktopAppLocator.bundleIdentifier],
        readOnlyBackend: any ComputerUseAutomationBackend = OpenComputerUseAutomationBackend(snapshotConfiguration: .nonIntrusive),
        controlBackend: any ComputerUseAutomationBackend = OpenComputerUseAutomationBackend(snapshotConfiguration: .default)
    ) {
        self.allowedApps = Set(allowedApps.map(Self.normalizedAppIdentifier(_:)))
        self.readOnlyBackend = readOnlyBackend
        self.controlBackend = controlBackend
    }

    func getAppSnapshot(app: String, policy: ComputerUseAutomationPolicy) throws -> ComputerUseAutomationSnapshot {
        try validateApp(app)
        return try withGlobalPointerFallbacks(enabled: false) {
            try backend(for: policy).getAppSnapshot(app: app)
        }
    }

    func getAppState(app: String, policy: ComputerUseAutomationPolicy) throws -> String {
        try validateApp(app)
        return try withGlobalPointerFallbacks(enabled: false) {
            try backend(for: policy).getAppState(app: app)
        }
    }

    func click(app: String, elementIndex: String, policy: ComputerUseAutomationPolicy) throws -> String {
        try validateApp(app)
        try validateAction(policy)
        return try withGlobalPointerFallbacks(enabled: false) {
            try backend(for: policy).click(app: app, elementIndex: elementIndex)
        }
    }

    func click(
        app: String,
        x: Double,
        y: Double,
        policy: ComputerUseAutomationPolicy,
        allowsForegroundPointerFallback: Bool
    ) throws -> String {
        try validateApp(app)
        try validateAction(policy)
        try validateForegroundPointerFallback(app: app, allowsForegroundPointerFallback: allowsForegroundPointerFallback)
        return try withGlobalPointerFallbacks(enabled: allowsForegroundPointerFallback) {
            try backend(for: policy).click(app: app, x: x, y: y)
        }
    }

    func pressKey(app: String, key: String, policy: ComputerUseAutomationPolicy) throws -> String {
        try validateApp(app)
        try validateAction(policy)
        return try withGlobalPointerFallbacks(enabled: false) {
            try backend(for: policy).pressKey(app: app, key: key)
        }
    }

    func typeText(app: String, text: String, policy: ComputerUseAutomationPolicy) throws -> String {
        try validateApp(app)
        try validateAction(policy)
        return try withGlobalPointerFallbacks(enabled: false) {
            try backend(for: policy).typeText(app: app, text: text)
        }
    }

    func setValue(app: String, elementIndex: String, value: String, policy: ComputerUseAutomationPolicy) throws -> String {
        try validateApp(app)
        try validateAction(policy)
        return try withGlobalPointerFallbacks(enabled: false) {
            try backend(for: policy).setValue(app: app, elementIndex: elementIndex, value: value)
        }
    }

    private func backend(for policy: ComputerUseAutomationPolicy) -> any ComputerUseAutomationBackend {
        switch policy {
        case .readOnly:
            readOnlyBackend
        case .userInitiatedControl:
            controlBackend
        }
    }

    private func validateApp(_ app: String) throws {
        guard allowedApps.contains(Self.normalizedAppIdentifier(app)) else {
            throw ComputerUseAutomationError.appNotAllowed(app)
        }
    }

    private func validateAction(_ policy: ComputerUseAutomationPolicy) throws {
        guard policy.allowsActions else {
            throw ComputerUseAutomationError.actionNotAllowed
        }
    }

    private func validateForegroundPointerFallback(app: String, allowsForegroundPointerFallback: Bool) throws {
        guard allowsForegroundPointerFallback else { return }
        guard Self.normalizedAppIdentifier(app) == Self.normalizedAppIdentifier(ClaudeDesktopAppLocator.bundleIdentifier) else {
            throw ComputerUseAutomationError.foregroundPointerFallbackNotAllowed(app)
        }
    }

    private func withGlobalPointerFallbacks<T>(enabled: Bool, _ body: () throws -> T) throws -> T {
        let key = Self.globalPointerFallbackEnvironmentKey
        let previousValue = getenv(key).map { String(cString: $0) }
        if enabled {
            setenv(key, "1", 1)
        } else {
            unsetenv(key)
        }
        defer {
            if let previousValue {
                setenv(key, previousValue, 1)
            } else {
                unsetenv(key)
            }
        }
        return try body()
    }

    private static func normalizedAppIdentifier(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

private extension ComputerUseAutomationSnapshot {
    init(openSnapshot: AppSnapshot) {
        self.init(
            text: openSnapshot.renderedText,
            windowSize: openSnapshot.windowBounds?.size,
            screenshotPixelSize: openSnapshot.screenshotPixelSize,
            elements: openSnapshot.elementDescriptors.map(ComputerUseAutomationElement.init(descriptor:))
        )
    }
}

private extension ComputerUseAutomationElement {
    init(descriptor: ComputerUseElementDescriptor) {
        self.init(
            index: "\(descriptor.index)",
            role: descriptor.role,
            label: descriptor.renderedLine,
            actions: descriptor.actions,
            frame: descriptor.frame,
            isSyntheticText: descriptor.isSyntheticText
        )
    }
}
