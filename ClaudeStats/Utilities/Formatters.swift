import Foundation

/// Small display formatters shared across views.
enum Format {
    /// Compact token counts: `847`, `12.3K`, `4.1M`, `2.0B`.
    static func tokens(_ count: Int) -> String {
        let n = Double(count)
        switch abs(count) {
        case 1_000_000_000...: return trim(n / 1_000_000_000) + "B"
        case 1_000_000...:     return trim(n / 1_000_000) + "M"
        case 1_000...:         return trim(n / 1_000) + "K"
        default:               return "\(count)"
        }
    }

    /// `$0.00`, `$1.23`, `$12.34`. Always two decimals; never localizes the
    /// currency symbol away (this is an estimate, not a billing figure).
    static func cost(_ amount: Double) -> String {
        String(format: "$%.2f", amount)
    }

    static func relativeDate(_ date: Date, now: Date = .now) -> String {
        let fmt = RelativeDateTimeFormatter()
        fmt.unitsStyle = .abbreviated
        return fmt.localizedString(for: date, relativeTo: now)
    }

    static func shortDate(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    /// Day only, no year: `May 1`, `Dec 12`.
    static func day(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day())
    }

    /// Compact duration: `0m`, `7m`, `1h 04m`, `3h`. Rounds to the minute.
    static func duration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let minutes = total / 60
        let h = minutes / 60
        let m = minutes % 60
        if h == 0 { return "\(m)m" }
        return m == 0 ? "\(h)h" : String(format: "%dh %02dm", h, m)
    }

    /// `0%`, `48%`, `100%` from a `0...1` ratio.
    static func percent(_ ratio: Double) -> String {
        "\(Int((ratio * 100).rounded()))%"
    }

    private static func trim(_ value: Double) -> String {
        // One decimal place, but drop a trailing `.0`.
        let s = String(format: "%.1f", value)
        return s.hasSuffix(".0") ? String(s.dropLast(2)) : s
    }
}
