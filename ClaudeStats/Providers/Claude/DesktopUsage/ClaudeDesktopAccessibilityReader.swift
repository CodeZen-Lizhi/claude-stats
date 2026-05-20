import ApplicationServices
import Foundation

@MainActor
protocol ClaudeDesktopUsageTextReading: AnyObject {
    func readUsageText(app: ClaudeDesktopAppState, trigger: ClaudeDesktopUsageCaptureTrigger) async throws -> String
}

@MainActor
final class ClaudeDesktopAccessibilityReader: ClaudeDesktopUsageTextReading {
    private let maxDepth = 12
    private let maxNodes = 900

    func readUsageText(app: ClaudeDesktopAppState, trigger: ClaudeDesktopUsageCaptureTrigger) async throws -> String {
        guard let pid = app.processIdentifier else {
            throw ClaudeDesktopUsageCaptureError.appNotRunning
        }
        guard isTrusted(prompt: trigger.promptsForPermissions) else {
            throw ClaudeDesktopUsageCaptureError.accessibilityPermissionRequired
        }

        let appElement = AXUIElementCreateApplication(pid)
        var text = collectText(from: appElement)
        if looksLikeUsageText(text) {
            return text
        }

        if pressUsageCandidate(in: appElement) {
            try? await Task.sleep(nanoseconds: 350_000_000)
            text = collectText(from: appElement)
            if !text.isEmpty {
                return text
            }
        }

        throw ClaudeDesktopUsageCaptureError.noUsageText
    }

    private func isTrusted(prompt: Bool) -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    private func collectText(from root: AXUIElement) -> String {
        var strings: [String] = []
        var visited = 0
        collectText(from: root, depth: 0, visited: &visited, strings: &strings)
        return strings
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .uniqued()
            .joined(separator: "\n")
    }

    private func collectText(from element: AXUIElement, depth: Int, visited: inout Int, strings: inout [String]) {
        guard depth <= maxDepth, visited < maxNodes else { return }
        visited += 1

        for attribute in Self.textAttributes {
            if let value = copyAttribute(attribute, from: element) {
                appendText(from: value, to: &strings)
            }
        }

        guard let children = copyAttribute("AXChildren", from: element) as? [AXUIElement] else { return }
        for child in children {
            collectText(from: child, depth: depth + 1, visited: &visited, strings: &strings)
        }
    }

    private func pressUsageCandidate(in root: AXUIElement) -> Bool {
        var visited = 0
        guard let candidate = usageCandidate(in: root, depth: 0, visited: &visited) else { return false }
        return AXUIElementPerformAction(candidate, "AXPress" as CFString) == .success
    }

    private func usageCandidate(in element: AXUIElement, depth: Int, visited: inout Int) -> AXUIElement? {
        guard depth <= maxDepth, visited < maxNodes else { return nil }
        visited += 1

        let label = Self.textAttributes
            .compactMap { copyAttribute($0, from: element) }
            .compactMap { stringValue(from: $0) }
            .joined(separator: " ")
            .lowercased()
        let role = (copyAttribute("AXRole", from: element) as? String) ?? ""
        if isPressable(element), isUsageLabel(label), Self.pressableRoles.contains(role) {
            return element
        }

        guard let children = copyAttribute("AXChildren", from: element) as? [AXUIElement] else { return nil }
        for child in children {
            if let candidate = usageCandidate(in: child, depth: depth + 1, visited: &visited) {
                return candidate
            }
        }
        return nil
    }

    private func isPressable(_ element: AXUIElement) -> Bool {
        var actionNames: CFArray?
        guard AXUIElementCopyActionNames(element, &actionNames) == .success,
              let names = actionNames as? [String] else {
            return false
        }
        return names.contains("AXPress")
    }

    private func isUsageLabel(_ label: String) -> Bool {
        guard !label.isEmpty else { return false }
        return label.contains("usage")
            || label.contains("limit")
            || label.contains("remaining")
            || label.contains("left")
            || label.contains("用量")
            || label.contains("限制")
            || label.contains("剩余")
            || label.contains("%")
    }

    private func looksLikeUsageText(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("%")
            && (lower.contains("5h") || lower.contains("5 hour") || lower.contains("5小时") || lower.contains("weekly") || lower.contains("7d") || lower.contains("7天") || lower.contains("周"))
    }

    private func appendText(from value: AnyObject, to strings: inout [String]) {
        if let string = stringValue(from: value) {
            strings.append(string)
        } else if let array = value as? [AnyObject] {
            for item in array {
                appendText(from: item, to: &strings)
            }
        }
    }

    private func stringValue(from value: AnyObject) -> String? {
        if let string = value as? String {
            string
        } else if let attributed = value as? NSAttributedString {
            attributed.string
        } else if let number = value as? NSNumber {
            number.stringValue
        } else {
            nil
        }
    }

    private func copyAttribute(_ attribute: String, from element: AXUIElement) -> AnyObject? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as AnyObject?
    }

    private static let textAttributes: [String] = [
        "AXTitle",
        "AXValue",
        "AXDescription",
        "AXHelp",
    ]

    private static let pressableRoles: Set<String> = [
        "AXButton",
        "AXMenuButton",
        "AXPopUpButton",
    ]
}

private extension Array where Element == String {
    func uniqued() -> [String] {
        var seen: Set<String> = []
        return filter { seen.insert($0).inserted }
    }
}
