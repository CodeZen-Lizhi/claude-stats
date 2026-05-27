# brainstorm: performance optimization analysis

## Goal

Find the remaining causes of Codex Statistics feeling slow: data loading is slow, menu/view switching is slow, and the app can occasionally freeze. Produce a performance-first optimization plan that keeps existing features unchanged. Large refactors are acceptable when they materially improve responsiveness, memory use, and scalability.

## What I already know

* User reports: app feels laggy, data fetch is slow, menu switching is slow, and occasional freezes happen.
* User preference: do not change code yet; list all likely problems and solutions first.
* User priority: functionality must remain unchanged; performance matters more than implementation size.
* The app is a macOS SwiftUI menu-bar app using Swift 6 strict concurrency.
* Stores and view models are commonly `@MainActor @Observable`; file scanning/parsing is expected to run off the main actor.
* Existing instructions require `bash scripts/run-debug.sh` after code changes, but this analysis step does not change app code.
* Current working tree already contains uncommitted user/other changes in Swift files and specs; do not overwrite them.
* Previous package-size research found `/Applications/Codex Statistics.app` around 155 MB, mostly from `Contents/Resources/GitTools` around 137 MB.
* Installed idle memory was measured around 56 MB physical footprint in one run, with higher peaks observed; user screenshot reported much higher memory, likely from active data/Git paths or app-specific memory accounting.
* Current `~/.codex` JSONL files observed earlier were not large, so latency may come from repeated full refresh, repeated aggregation, or UI-triggered recomputation rather than raw file size alone.
* Current local `~/.codex/sessions` is about 133 MB, with 51 `rollout-*.jsonl` files and about 39,641 total lines. Three rollout files are larger than 10 MB; the largest is about 28 MB.
* Current `Codex Statistics` usage ledger is about 5.8 MB, with 8,086 events and 75 parse states.
* Reading the ledger JSON with Python took about 23-26 ms locally, so the ledger file itself is not huge, but repeated full-array scans are still avoidable.

## Assumptions (temporary)

* Slow paths are primarily CPU, file I/O, process spawning, and main-actor contention rather than network latency.
* Occasional freezes may come from main-actor publication of large snapshots, synchronous aggregation during view changes, or external Git tool work overlapping UI work.
* Feature behavior should remain byte-for-byte or UX-equivalent unless a performance trade-off is explicitly approved.

## Open Questions

* Which optimization phase should be implemented first after analysis: core session/usage responsiveness only, or all P0/P1 performance work together?

## Requirements (evolving)

* Preserve all existing user-visible features.
* Improve data refresh speed, view/menu switching latency, and freeze resistance.
* Reduce avoidable memory peaks during transcript parsing and usage aggregation.
* Avoid UI work that scales linearly with all historical events during normal navigation.
* Make expensive Git analysis progressive, cancellable, cached, or user-triggered.
* Add enough performance instrumentation to prove before/after improvements.

## Acceptance Criteria (evolving)

* [ ] Identify concrete bottlenecks with code anchors and expected impact.
* [ ] Produce prioritized solution list covering session scanning, transcript parsing, usage ledger, UI derivation, Git stats, memory footprint, and packaging/runtime size.
* [ ] Define measurable performance targets before implementation.
* [ ] Define a validation plan that can catch regressions without relying only on subjective feel.

## Definition of Done (team quality bar)

* Tests added/updated when implementation starts.
* Lint / typecheck / CI green when implementation starts.
* Docs/notes updated if behavior changes.
* Rollout/rollback considered if risky.
* Performance metrics collected before and after core changes.

## Out of Scope (explicit)

* No app-code changes during this analysis round.
* No feature removal.
* No release or packaging action during this analysis round.

## Technical Notes

* Key files to inspect:
  * `ClaudeStats/Services/SessionStore.swift`
  * `ClaudeStats/Services/UsageLedgerStore.swift`
  * `ClaudeStats/Providers/Codex/CodexTranscriptParser.swift`
  * `ClaudeStats/Providers/Codex/CodexSessionScanner.swift`
  * `ClaudeStats/ViewModels/SessionListViewModel.swift`
  * `ClaudeStats/Views/MainWindow/Sessions/SessionSidebarColumn.swift`
  * `ClaudeStats/Views/Dashboard/DashboardView.swift`
  * `ClaudeStats/Views/Usage/MainUsageView.swift`
  * `ClaudeStats/Services/Git/Stats/GitRepoStatsService.swift`
  * `ClaudeStats/Services/Git/Stats/GitCodeOwnershipAnalyzer.swift`
  * `ClaudeStats/Services/Git/Linguist/GitLinguistAnalyzer.swift`
  * `ClaudeStats/ViewModels/GitRepoGraphViewModel.swift`
* Early hotspot hypotheses:
  * `SessionStore.refresh()` does full discovery, parse/cache checks, ledger stats, full usage event snapshot, and session graph rebuild.
  * `UsageLedgerStore.stats(for:)` appears to filter/sort all events per session, causing `sessions x events` scaling.
  * `UsageLedgerStore.replaceEvents`, `clearEvents`, `appendEvents`, and `upsertParseState` use full-array operations (`removeAll`, full event-key Set, `firstIndex`) for per-session updates.
  * `CodexTranscriptParser.parse()` reads whole transcript files into memory and splits them.
  * `CodexTranscriptParser.messages()` and `taskIntervals()` also read whole transcript files into memory, so opening a large session detail can repeat large allocations.
  * `UsageDerivedData.make()` runs `UsageSummary.make`, `trendSeries`, and cache-hit derivation on the main actor during Usage view appearance/change.
  * `DashboardView` passes `env.store.usageEventsSnapshot()` into a background reload; the expensive aggregation is detached, but first the full events array is copied/filtered from the main-actor store.
  * `MenuBarLabel` and floating stats compute `env.store.summary(...)` directly in `body`, so unrelated observation invalidations can re-run full summary aggregation.
  * `SessionListViewModel.refresh()` compares full `[Session]` arrays and rebuilds all project groups when source sessions or cost mode changes.
  * `SessionDetailView` rebuilds `TranscriptSearchIndex` in `body`, then `TranscriptSearchIndex.matches(for:)` filters all matches per rendered message.
  * `AppEnvironment.start()` triggers `store.refresh()` on launch and auto-refresh defaults to 5 minutes, so any refresh inefficiency recurs in the background.
  * `GitActivityView` / `MainGitActivityView` reload on `env.store.lastRefreshedAt`, which can make every session refresh also recompute Git activity correlations.
  * `GitRepoStatsService` contains heavy external-tool paths (`github-linguist`, `scc`, per-file `git blame`). In the current tree `loadRepoStats` is not directly wired by views, but if enabled it must be progressive/lazy.
  * Git ownership analysis can run many `git blame` jobs and external tools.
  * SwiftUI `.task`, `.onAppear`, and `.onChange` chains may recompute derived usage/session data during menu switching.
