import Foundation

struct ClaudeDesktopUsageTextParser: Sendable {
    func snapshot(from text: String, capturedAt: Date = .now) -> UsageLimitSnapshot? {
        let windows = Self.windowDefinitions.compactMap { definition in
            usageWindow(definition: definition, in: text, capturedAt: capturedAt)
        }

        guard !windows.isEmpty else { return nil }
        return UsageLimitSnapshot(
            provider: .claude,
            windows: windows,
            capturedAt: capturedAt,
            sourceLabel: "Claude Desktop UI",
            sourcePath: UsageLimitCachePaths.claudeCacheURL().path,
            planType: nil,
            limitID: "claude-desktop-ui"
        )
    }

    private func usageWindow(
        definition: UsageWindowDefinition,
        in text: String,
        capturedAt: Date
    ) -> UsageLimitWindow? {
        guard let segment = segment(for: definition, in: text) else { return nil }
        guard let usedPercent = usedPercent(in: segment) else { return nil }
        return UsageLimitWindow(
            id: definition.id,
            label: definition.label,
            usedPercent: min(100, max(0, usedPercent)),
            resetAt: resetDate(in: segment, capturedAt: capturedAt),
            windowMinutes: definition.minutes
        )
    }

    private func segment(for definition: UsageWindowDefinition, in text: String) -> String? {
        let prepared = text
            .replacingOccurrences(of: "\u{ff05}", with: "%")
            .replacingOccurrences(of: "\u{00a0}", with: " ")
        let lowercase = prepared.lowercased()

        guard let markerRange = definition.markers.compactMap({ lowercase.range(of: $0, options: .regularExpression) }).min(by: { $0.lowerBound < $1.lowerBound }) else {
            return nil
        }

        let otherMarkers = Self.windowDefinitions
            .filter { $0.id != definition.id }
            .flatMap(\.markers)
        let rest = lowercase[markerRange.upperBound...]
        let nextMarker = otherMarkers
            .compactMap { rest.range(of: $0, options: .regularExpression)?.lowerBound }
            .min()
        let upperBound = nextMarker ?? lowercase.endIndex
        return String(lowercase[markerRange.lowerBound..<upperBound])
    }

    private func usedPercent(in text: String) -> Double? {
        if let used = firstNumber(
            in: text,
            patterns: [
                #"(?i)(\d+(?:\.\d+)?)\s*%\s*(?:used|usage|已用|已使用|使用|用量)"#,
                #"(?i)(?:used|usage|已用|已使用|使用|用量)[^\d%]{0,16}(\d+(?:\.\d+)?)\s*%"#,
            ]
        ) {
            return used
        }

        if let remaining = firstNumber(
            in: text,
            patterns: [
                #"(?i)(\d+(?:\.\d+)?)\s*%\s*(?:left|remaining|remain|剩余|剩餘|可用)"#,
                #"(?i)(?:left|remaining|remain|剩余|剩餘|可用)[^\d%]{0,16}(\d+(?:\.\d+)?)\s*%"#,
            ]
        ) {
            return 100 - remaining
        }

        return bareUsedPercent(in: text)
    }

    private func bareUsedPercent(in text: String) -> Double? {
        firstNumber(
            in: text,
            patterns: [
                #"(?i)(\d+(?:\.\d+)?)\s*%"#,
            ]
        )
    }

    private func resetDate(in text: String, capturedAt: Date) -> Date? {
        if let hours = firstNumber(
            in: text,
            patterns: [
                #"(?i)(?:resets?|reset|重置|刷新)[^\d]{0,24}(\d+(?:\.\d+)?)\s*(?:h|hr|hrs|hour|hours|小时|小時)"#,
                #"(?i)(\d+(?:\.\d+)?)\s*(?:h|hr|hrs|hour|hours|小时|小時)[^\n]{0,18}(?:reset|resets|left|后重置|後重置|后刷新|後刷新)"#,
            ]
        ) {
            return capturedAt.addingTimeInterval(hours * 3_600)
        }

        if let days = firstNumber(
            in: text,
            patterns: [
                #"(?i)(?:resets?|reset|重置|刷新)[^\d]{0,24}(\d+(?:\.\d+)?)\s*(?:d|day|days|天|日)"#,
                #"(?i)(\d+(?:\.\d+)?)\s*(?:d|day|days|天|日)[^\n]{0,18}(?:reset|resets|left|后重置|後重置|后刷新|後刷新)"#,
            ]
        ) {
            return capturedAt.addingTimeInterval(days * 86_400)
        }

        if let minutes = firstNumber(
            in: text,
            patterns: [
                #"(?i)(?:resets?|reset|重置|刷新)[^\d]{0,24}(\d+(?:\.\d+)?)\s*(?:m|min|mins|minute|minutes|分钟|分鐘)"#,
                #"(?i)(\d+(?:\.\d+)?)\s*(?:m|min|mins|minute|minutes|分钟|分鐘)[^\n]{0,18}(?:reset|resets|left|后重置|後重置|后刷新|後刷新)"#,
            ]
        ) {
            return capturedAt.addingTimeInterval(minutes * 60)
        }

        return nil
    }

    private func firstNumber(in text: String, patterns: [String]) -> Double? {
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            guard let match = regex.firstMatch(in: text, range: range),
                  match.numberOfRanges > 1,
                  let captureRange = Range(match.range(at: 1), in: text) else {
                continue
            }
            if let value = Double(text[captureRange]) {
                return value
            }
        }
        return nil
    }

    private static let windowDefinitions = [
        UsageWindowDefinition(
            id: "five_hour",
            label: "5h",
            minutes: 300,
            markers: [
                #"(?i)\b5\s*h\b"#,
                #"(?i)\b5\s*(?:-|–|—)?\s*hours?\b"#,
                #"5\s*小时"#,
                #"5\s*小時"#,
                #"五\s*小时"#,
                #"五\s*小時"#,
            ]
        ),
        UsageWindowDefinition(
            id: "seven_day",
            label: "7d",
            minutes: 10_080,
            markers: [
                #"(?i)\bweekly\b\s*(?:·|-|–|—)\s*all\s+models\b"#,
                #"(?i)\b7\s*d\b"#,
                #"(?i)\b7\s*days?\b"#,
                #"(?i)\bweekly\b(?!\s*(?:·|-|–|—)\s*(?:all\s+models|claude\s+design))"#,
                #"(?i)\bweek\b"#,
                #"7\s*天"#,
                #"七\s*天"#,
                #"每周"#,
                #"每週"#,
                #"周"#,
                #"週"#,
            ]
        ),
        UsageWindowDefinition(
            id: "weekly_claude_design",
            label: "Claude Design",
            minutes: 10_080,
            markers: [
                #"(?i)\bweekly\b\s*(?:·|-|–|—)\s*claude\s+design\b"#,
                #"(?i)\bclaude\s+design\b"#,
            ]
        ),
        UsageWindowDefinition(
            id: "sonnet_only",
            label: "Sonnet",
            minutes: 10_080,
            markers: [
                #"(?i)\bsonnet\s+only\b"#,
            ]
        ),
    ]
}

private struct UsageWindowDefinition: Sendable {
    let id: String
    let label: String
    let minutes: Int
    let markers: [String]
}
