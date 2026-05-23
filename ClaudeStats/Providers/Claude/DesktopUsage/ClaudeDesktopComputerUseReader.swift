import Foundation
import CoreGraphics

@MainActor
final class ClaudeDesktopComputerUseReader: ClaudeDesktopUsageTextReading {
    private let automation: any ComputerUseAutomating
    private let parser: ClaudeDesktopUsageTextParser
    private let maxTextCandidateClicks = 6
    private let maxFrameCandidateClicks = 4

    init(
        automation: any ComputerUseAutomating = ComputerUseAutomationService(),
        parser: ClaudeDesktopUsageTextParser = ClaudeDesktopUsageTextParser()
    ) {
        self.automation = automation
        self.parser = parser
    }

    func readUsageText(app: ClaudeDesktopAppState, trigger: ClaudeDesktopUsageCaptureTrigger) async throws -> String {
        guard app.isRunning else {
            throw ClaudeDesktopUsageCaptureError.appNotRunning
        }

        let policy = trigger.computerUseAutomationPolicy
        do {
            let appIdentifier = ClaudeDesktopAppLocator.bundleIdentifier
            let initialSnapshot = try automation.getAppSnapshot(app: appIdentifier, policy: policy)
            if containsParseableUsage(in: initialSnapshot.text) {
                logManual(trigger, "ComputerUse snapshot already contains parseable Claude usage.")
                return initialSnapshot.text
            }

            guard policy.allowsActions else {
                logManual(trigger, "ComputerUse automatic snapshot is not parseable; staying read-only.")
                throw ClaudeDesktopUsageCaptureError.noUsageText
            }

            let textCandidates = usageCandidateElementIndices(in: initialSnapshot)
            logManual(trigger, "ComputerUse usage text candidates: \(textCandidates.count)")
            for elementIndex in textCandidates.prefix(maxTextCandidateClicks) {
                if let text = await clickElementAndReadUsage(
                    appIdentifier: appIdentifier,
                    elementIndex: elementIndex,
                    policy: policy,
                    trigger: trigger,
                    label: "text candidate"
                ) {
                    return text
                }
            }

            let frameCandidates = bottomTrailingUsageCandidateElementIndices(in: initialSnapshot)
            logManual(trigger, "ComputerUse bottom-right frame candidates: \(frameCandidates.count)")
            for elementIndex in frameCandidates.prefix(maxFrameCandidateClicks) {
                if let text = await clickElementAndReadUsage(
                    appIdentifier: appIdentifier,
                    elementIndex: elementIndex,
                    policy: policy,
                    trigger: trigger,
                    label: "frame candidate"
                ) {
                    return text
                }
            }

            if let text = await clickFallbackCoordinateAndReadUsage(
                appIdentifier: appIdentifier,
                snapshot: initialSnapshot,
                policy: policy,
                trigger: trigger
            ) {
                return text
            }

            throw ClaudeDesktopUsageCaptureError.noUsageText
        } catch let error as ClaudeDesktopUsageCaptureError {
            throw error
        } catch let error as ComputerUseAutomationError where error.isAccessibilityPermissionFailure {
            if trigger.promptsForPermissions {
                ClaudeDesktopAccessibilityPermissionDiagnostics.logNotTrusted(context: "computer use reader")
            }
            throw ClaudeDesktopUsageCaptureError.accessibilityPermissionRequired
        } catch {
            throw ClaudeDesktopUsageCaptureError.captureFailed(error.localizedDescription)
        }
    }

    private func containsParseableUsage(in text: String) -> Bool {
        parser.snapshot(from: text) != nil
    }

    private func clickElementAndReadUsage(
        appIdentifier: String,
        elementIndex: String,
        policy: ComputerUseAutomationPolicy,
        trigger: ClaudeDesktopUsageCaptureTrigger,
        label: String
    ) async -> String? {
        do {
            let actionText = try automation.click(app: appIdentifier, elementIndex: elementIndex, policy: policy)
            if containsParseableUsage(in: actionText) {
                logManual(trigger, "ComputerUse \(label) \(elementIndex) returned parseable usage.")
                return actionText
            }
        } catch {
            logManual(trigger, "ComputerUse \(label) \(elementIndex) click failed: \(error.localizedDescription)")
        }

        try? await Task.sleep(nanoseconds: 500_000_000)

        do {
            let refreshedSnapshot = try automation.getAppSnapshot(app: appIdentifier, policy: policy)
            if containsParseableUsage(in: refreshedSnapshot.text) {
                logManual(trigger, "ComputerUse \(label) \(elementIndex) opened usage after refresh.")
                return refreshedSnapshot.text
            }
        } catch {
            logManual(trigger, "ComputerUse refresh after \(label) \(elementIndex) failed: \(error.localizedDescription)")
        }

        return nil
    }

    private func clickFallbackCoordinateAndReadUsage(
        appIdentifier: String,
        snapshot: ComputerUseAutomationSnapshot,
        policy: ComputerUseAutomationPolicy,
        trigger: ClaudeDesktopUsageCaptureTrigger
    ) async -> String? {
        guard trigger.allowsForegroundPointerFallback,
              let point = usageFallbackScreenshotPoint(in: snapshot) else {
            return nil
        }

        do {
            let actionText = try automation.click(
                app: appIdentifier,
                x: point.x,
                y: point.y,
                policy: policy,
                allowsForegroundPointerFallback: true
            )
            if containsParseableUsage(in: actionText) {
                logManual(trigger, "ComputerUse foreground coordinate fallback returned parseable usage.")
                return actionText
            }
        } catch {
            logManual(trigger, "ComputerUse foreground coordinate fallback failed: \(error.localizedDescription)")
        }

        try? await Task.sleep(nanoseconds: 550_000_000)

        do {
            let refreshedSnapshot = try automation.getAppSnapshot(app: appIdentifier, policy: policy)
            if containsParseableUsage(in: refreshedSnapshot.text) {
                logManual(trigger, "ComputerUse foreground coordinate fallback opened usage after refresh.")
                return refreshedSnapshot.text
            }
        } catch {
            logManual(trigger, "ComputerUse refresh after foreground coordinate fallback failed: \(error.localizedDescription)")
        }

        return nil
    }

    private func usageCandidateElementIndices(in snapshot: ComputerUseAutomationSnapshot) -> [String] {
        var indices: [String] = []
        var seen: Set<String> = []

        for element in snapshot.elements {
            guard isUsageCandidateLine(element.label),
                  seen.insert(element.index).inserted else {
                continue
            }
            indices.append(element.index)
        }

        return indices
    }

    private func bottomTrailingUsageCandidateElementIndices(in snapshot: ComputerUseAutomationSnapshot) -> [String] {
        guard let windowSize = snapshot.windowSize else { return [] }
        let fallbackTarget = usageFallbackWindowPoint(windowSize: windowSize)
        let minimumX = windowSize.width * 0.62
        let minimumY = max(windowSize.height - 170, 0)

        return snapshot.elements
            .filter { element in
                guard let frame = element.frame else { return false }
                return frame.midX >= minimumX
                    && frame.midY >= minimumY
                    && frame.width >= 8
                    && frame.height >= 8
                    && frame.width <= 140
                    && frame.height <= 90
                    && isBottomUsageCandidateRole(element.role, label: element.label)
            }
            .sorted { lhs, rhs in
                let lhsDistance = distance(from: lhs.frame?.center ?? .zero, to: fallbackTarget)
                let rhsDistance = distance(from: rhs.frame?.center ?? .zero, to: fallbackTarget)
                if abs(lhsDistance - rhsDistance) > 0.001 {
                    return lhsDistance < rhsDistance
                }
                return (lhs.frame?.midX ?? 0) > (rhs.frame?.midX ?? 0)
            }
            .map(\.index)
    }

    private func isUsageCandidateLine(_ line: String) -> Bool {
        let label = line.lowercased()
        guard !label.isEmpty else { return false }
        return label.contains("plan usage")
            || label.contains("usage limits")
            || label.contains("usage")
            || label.contains("limit")
            || label.contains("remaining")
            || label.contains("left")
            || label.contains("用量")
            || label.contains("限制")
            || label.contains("剩余")
            || label.contains("剩餘")
            || label.contains("%")
    }

    private func isBottomUsageCandidateRole(_ role: String, label: String) -> Bool {
        let combined = "\(role) \(label)".lowercased()
        return combined.contains("button")
            || combined.contains("image")
            || combined.contains("group")
            || combined.contains("svg")
            || combined.contains("unknown")
    }

    private func usageFallbackScreenshotPoint(in snapshot: ComputerUseAutomationSnapshot) -> CGPoint? {
        guard let windowSize = snapshot.windowSize else { return nil }
        return snapshot.screenshotPoint(forWindowPoint: usageFallbackWindowPoint(windowSize: windowSize))
    }

    private func usageFallbackWindowPoint(windowSize: CGSize) -> CGPoint {
        CGPoint(
            x: max(windowSize.width - 88, 1),
            y: max(windowSize.height - 58, 1)
        )
    }

    private func distance(from lhs: CGPoint, to rhs: CGPoint) -> CGFloat {
        let deltaX = lhs.x - rhs.x
        let deltaY = lhs.y - rhs.y
        return ((deltaX * deltaX) + (deltaY * deltaY)).squareRoot()
    }

    private func logManual(_ trigger: ClaudeDesktopUsageCaptureTrigger, _ message: String) {
        guard trigger.logsComputerUseDiagnostics else { return }
        Log.app.debug("\(message, privacy: .public)")
    }
}

private extension ClaudeDesktopUsageCaptureTrigger {
    var computerUseAutomationPolicy: ComputerUseAutomationPolicy {
        allowsActivation ? .userInitiatedControl : .readOnly
    }

    var allowsForegroundPointerFallback: Bool {
        self == .manual || self == .permissionRecheck
    }

    var logsComputerUseDiagnostics: Bool {
        self == .manual
    }
}

private extension CGRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }
}
