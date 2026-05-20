import Foundation

struct ClaudeDesktopUsageTextParser: Sendable {
    func snapshot(from text: String, capturedAt: Date = .now) -> UsageLimitSnapshot? {
        let windows = [
            usageWindow(id: "five_hour", label: "5h", minutes: 300, markers: Self.fiveHourMarkers, in: text, capturedAt: capturedAt),
            usageWindow(id: "seven_day", label: "7d", minutes: 10_080, markers: Self.sevenDayMarkers, in: text, capturedAt: capturedAt),
        ].compactMap { $0 }

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
        id: String,
        label: String,
        minutes: Int,
        markers: [String],
        in text: String,
        capturedAt: Date
    ) -> UsageLimitWindow? {
        guard let segment = segment(for: markers, in: text) else { return nil }
        guard let usedPercent = usedPercent(in: segment) else { return nil }
        return UsageLimitWindow(
            id: id,
            label: label,
            usedPercent: min(100, max(0, usedPercent)),
            resetAt: resetDate(in: segment, capturedAt: capturedAt),
            windowMinutes: minutes
        )
    }

    private func segment(for markers: [String], in text: String) -> String? {
        let prepared = text
            .replacingOccurrences(of: "\u{ff05}", with: "%")
            .replacingOccurrences(of: "\u{00a0}", with: " ")
        let lowercase = prepared.lowercased()

        guard let markerRange = markers.compactMap({ lowercase.range(of: $0, options: .regularExpression) }).min(by: { $0.lowerBound < $1.lowerBound }) else {
            return nil
        }

        let otherMarkers = (Self.fiveHourMarkers + Self.sevenDayMarkers)
            .filter { !markers.contains($0) }
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

        return nil
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

    private static let fiveHourMarkers = [
        #"(?i)\b5\s*h\b"#,
        #"(?i)\b5\s*hour"#,
        #"5\s*小时"#,
        #"5\s*小時"#,
        #"五\s*小时"#,
        #"五\s*小時"#,
    ]

    private static let sevenDayMarkers = [
        #"(?i)\b7\s*d\b"#,
        #"(?i)\b7\s*day"#,
        #"(?i)\bweekly\b"#,
        #"(?i)\bweek\b"#,
        #"7\s*天"#,
        #"七\s*天"#,
        #"每周"#,
        #"每週"#,
        #"周"#,
        #"週"#,
    ]
}
