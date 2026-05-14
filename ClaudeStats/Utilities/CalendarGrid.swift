import Foundation

/// A GitHub-style calendar grid: an array of week columns, each holding 7 day
/// starts in calendar order (`firstWeekday` first). Days that fall outside the
/// visible `range` are still emitted so every column is a full 7 — callers can
/// test inclusion with `range.contains(day)`.
///
/// The grid is built once from a `DateInterval` and rendered as a `LazyHGrid`
/// of 7 rows × N columns; row labels come from `weekdaySymbols`.
struct CalendarGrid: Sendable {
    /// The columns, oldest-week first. Inner arrays are always length 7.
    let weeks: [[Date]]
    /// Localized one-letter weekday symbols (M/T/W/…), aligned to the rows.
    let weekdaySymbols: [String]
    /// The interval the grid was built for. Useful for callers that want to
    /// filter out-of-range days during rendering.
    let range: DateInterval
    /// First weekday (1 = Sunday … 7 = Saturday) used to align rows.
    let firstWeekday: Int
    private let calendar: Calendar

    init(spanning range: DateInterval, calendar: Calendar = .current) {
        self.calendar = calendar
        self.range = range
        self.firstWeekday = calendar.firstWeekday

        let firstWeekStart = calendar.dateInterval(of: .weekOfYear, for: range.start)?.start ?? range.start
        let lastWeekStart = calendar.dateInterval(of: .weekOfYear, for: range.end)?.start ?? range.end

        var weeks: [[Date]] = []
        var cursor = firstWeekStart
        while cursor <= lastWeekStart {
            var days: [Date] = []
            for offset in 0..<7 {
                let day = calendar.date(byAdding: .day, value: offset, to: cursor) ?? cursor
                days.append(calendar.startOfDay(for: day))
            }
            weeks.append(days)
            guard let next = calendar.date(byAdding: .weekOfYear, value: 1, to: cursor), next > cursor else { break }
            cursor = next
        }
        self.weeks = weeks

        let standalone = calendar.veryShortStandaloneWeekdaySymbols
        let startIndex = firstWeekday - 1
        var rotated: [String] = []
        rotated.reserveCapacity(7)
        for i in 0..<7 {
            let idx = (startIndex + i) % 7
            rotated.append(idx < standalone.count ? standalone[idx] : "")
        }
        self.weekdaySymbols = rotated
    }

    /// Indices of weeks where the Monday-of-week (or the row that lands on the
    /// 1st of any month) starts a new month — for the month-label strip at the
    /// top of the grid. Returns `(weekIndex, abbreviated month)` pairs.
    func monthLabelPositions(calendar: Calendar = .current) -> [(weekIndex: Int, label: String)] {
        var out: [(Int, String)] = []
        var lastMonth = -1
        let fmt = DateFormatter()
        fmt.calendar = calendar
        fmt.locale = calendar.locale ?? .current
        fmt.dateFormat = "MMM"
        for (i, week) in weeks.enumerated() {
            // Use the first day of the week that's inside the visible range,
            // else the first day of the week.
            let representative = week.first(where: { range.contains($0) }) ?? week[0]
            let month = calendar.component(.month, from: representative)
            if month != lastMonth {
                out.append((i, fmt.string(from: representative)))
                lastMonth = month
            }
        }
        return out
    }
}
