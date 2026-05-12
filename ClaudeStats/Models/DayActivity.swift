import Foundation

/// The merged editor-vs-AI activity picture for a single calendar day.
///
/// All interval arrays are disjoint, sorted, and clipped to `day`. Durations
/// are precomputed (the analyzer already walked the intervals to build them).
struct DayActivity: Sendable, Hashable {
    /// The day this covers: `[start, start + 24h)` in the local calendar.
    let day: DateInterval
    /// Union of editor (IDE) focus intervals.
    let ideIntervals: [DateInterval]
    /// Union of Claude Code activity bursts.
    let aiIntervals: [DateInterval]
    /// `ideIntervals ∩ aiIntervals` — editor open *and* Claude active.
    let overlapIntervals: [DateInterval]

    let ideSeconds: TimeInterval
    let aiSeconds: TimeInterval
    let overlapSeconds: TimeInterval

    /// Editor time that had no concurrent Claude activity.
    var soloIDESeconds: TimeInterval { max(0, ideSeconds - overlapSeconds) }
    /// Claude activity with no editor focused (planning / reading / chat).
    var aiOnlySeconds: TimeInterval { max(0, aiSeconds - overlapSeconds) }

    /// Share of editor time spent with Claude also active. `0` when there was
    /// no editor time. *Not* a quality score — just a coincidence ratio.
    var assistedRatio: Double {
        ideSeconds > 0 ? overlapSeconds / ideSeconds : 0
    }

    var isEmpty: Bool { ideIntervals.isEmpty && aiIntervals.isEmpty }

    static func empty(day: DateInterval) -> DayActivity {
        DayActivity(day: day, ideIntervals: [], aiIntervals: [], overlapIntervals: [],
                    ideSeconds: 0, aiSeconds: 0, overlapSeconds: 0)
    }
}
