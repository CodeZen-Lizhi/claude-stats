import AppKit
@preconcurrency import ScreenCaptureKit
import Vision

@MainActor
final class ClaudeDesktopOCRReader: ClaudeDesktopUsageTextReading {
    func readUsageText(app: ClaudeDesktopAppState, trigger: ClaudeDesktopUsageCaptureTrigger) async throws -> String {
        guard app.isRunning else {
            throw ClaudeDesktopUsageCaptureError.appNotRunning
        }
        guard hasScreenCaptureAccess(prompt: trigger.promptsForPermissions) else {
            throw ClaudeDesktopUsageCaptureError.screenRecordingPermissionRequired
        }

        do {
            let image = try await captureClaudeWindow()
            let text = try recognizeText(in: image)
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ClaudeDesktopUsageCaptureError.noUsageText
            }
            return text
        } catch let error as ClaudeDesktopUsageCaptureError {
            throw error
        } catch {
            throw ClaudeDesktopUsageCaptureError.captureFailed(error.localizedDescription)
        }
    }

    private func hasScreenCaptureAccess(prompt: Bool) -> Bool {
        if CGPreflightScreenCaptureAccess() {
            return true
        }
        guard prompt else { return false }
        return CGRequestScreenCaptureAccess()
    }

    private func captureClaudeWindow() async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let window = content.windows.first(where: { window in
            window.owningApplication?.bundleIdentifier == ClaudeDesktopAppLocator.bundleIdentifier
        }) else {
            throw ClaudeDesktopUsageCaptureError.noUsageText
        }

        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let configuration = SCStreamConfiguration()
        configuration.width = max(1, Int(window.frame.width * scale))
        configuration.height = max(1, Int(window.frame.height * scale))
        configuration.showsCursor = false

        let filter = SCContentFilter(desktopIndependentWindow: window)
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }

    private func recognizeText(in image: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US", "zh-Hans"]
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: image)
        try handler.perform([request])
        return (request.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }
}
