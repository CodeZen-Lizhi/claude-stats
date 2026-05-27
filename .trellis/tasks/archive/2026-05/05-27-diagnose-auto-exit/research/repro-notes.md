# Repro Notes

## Environment

- Date: 2026-05-27
- Installed app observed: `/Applications/Codex Statistics.app`
- Installed bundle id: `com.claudestats.CodexStatistics`
- Installed version: `1.7.12 (17)`
- Build blocker for source debug run: `bash scripts/run-debug.sh` failed because active developer directory is `/Library/Developer/CommandLineTools`; no `/Applications/Xcode*.app` was present.

## Feedback Loop

Command shape:

```bash
PID=$(pgrep -f '/Applications/Codex Statistics.app/Contents/MacOS/Codex Statistics' | head -1)
for i in {1..36}; do
  kill -0 "$PID" || break
  ps -p "$PID" -o pid=,stat=,etime=,%cpu=,%mem=,command=
  sleep 5
done
```

Observed:

- PID `83402` started at `2026-05-27 13:05:16`.
- Monitor started at `2026-05-27 13:06:22`.
- The process was alive through tick 8 and exited at tick 9 (`2026-05-27 13:07:02`), about 40 seconds into observation.
- A new `/Applications/Codex Statistics.app` process appeared with PID `84122`, start time `2026-05-27 13:07:05`, parent PID `1`.
- No new crash report appeared immediately after the PID exit.

## Diagnostic Reports

Recent report:

- `/Library/Logs/DiagnosticReports/Codex Statistics_2026-05-27-130521_zhenglizhideMacBook-Pro.diag`
- Event: `disk writes`
- Action taken: `none`
- Writes: `2149.18 MB` file-backed memory dirtied over `4005` seconds.
- Heaviest stack: `AppEnvironment.start()` → `SessionStore.refresh()` → `UsageLedgerStore.persist()` → `Data.write(...)`.

Interpretation:

- This report is not a crash report; it is a resource diagnostic. It does not by itself prove the automatic exit.
- It does prove excessive write activity around usage ledger persistence.

## Code Facts

- `AppDelegate.applicationDidFinishLaunching` calls:
  - `AppLifecyclePolicy.configureAutomaticTermination()`
  - `AppLifecyclePolicy.reassertAfterLaunchRestoration()`
  - `env.start()`
- `AppLifecyclePolicy` disables automatic termination immediately and again 1 second after launch.
- The installed binary contains the string `Codex Statistics is a resident menu-bar app.`, so the installed version includes the automatic termination policy.
- The only app-level direct `NSApplication.shared.terminate(nil)` call found in source is the Quit button in `MenuPanelView`.
- `SessionStore.refresh()` calls `usageLedger.markSeen(discovered)` before deciding whether any session work is required.
- `UsageLedgerStore.markSeen` updates `lastSeenAt` for each live parse state and always calls `persist()`.
- `UsageLedgerStore.appendEvents`, `replaceEvents`, `clearEvents`, and `markUnviewable` also persist immediately.
- Current ledger file: `~/Library/Application Support/Codex Statistics/UsageLedger/usage-ledger.json`, about `3.4M`.

## Current Unknowns

- Why PID `83402` exited without a crash report.
- Whether launchd/background-item relaunch is hiding repeated exits.
- Whether macOS Automatic Termination can still occur despite `disableAutomaticTermination` under this launch path.
- Whether excessive ledger writes increase resource pressure enough to trigger system behavior in some environments.

## Fix Applied

- Confirmed the current codebase already contains `UsageLedgerStore` persistence batching so a single `SessionStore.refresh()` can coalesce multiple ledger mutations into one final atomic write.
- Confirmed `UsageLedgerStore.markSeen` avoids rewriting the ledger for unchanged live sessions.
- Confirmed regression tests exist covering:
  - unchanged `markSeen` does not rewrite the ledger or advance `lastSeenAt`;
  - batched persistence defers file creation until the batch ends and flushes the final snapshot.
- Added an explicit lifecycle-policy reassertion hook and call it after `DockVisibilityCoordinator` drops the app back from `.regular` to `.accessory`, covering main-window/Sparkle activation-policy round trips.

## Verification

- `python3 -B -m unittest discover scripts/tests` passed via `bash scripts/run-tests.sh` (`22` tests).
- Swift test/build verification is blocked in this environment because `xcodebuild` requires full Xcode, but `xcode-select -p` points to `/Library/Developer/CommandLineTools` and no `/Applications/Xcode*.app` was found.
- `bash scripts/run-debug.sh` is blocked by the same Xcode environment issue.

## Performance Follow-up: Sessions and Dashboard Feel Laggy

User reported that opening Sessions and Dashboard feels slightly laggy.

Observed local data size:

- `~/Library/Application Support/Codex Statistics/UsageLedger/usage-ledger.json` is about `3.5M`.
- Ledger contains `4784` events, `150` parse states, `146` unique event sessions, and `2` unique models.

Hypotheses tested from code inspection and process sampling:

1. Sessions overview repeatedly recomputes `UsageSummary.make(...)` in computed view properties. Confirmed: `summary`, `cacheHitRate`, cards, model table, and `ViewThatFits` paths could all touch the same aggregate during one body pass.
2. Dashboard reload runs every time `DashboardView` appears even when `env.dashboard` already has current data. Confirmed: `.task(id:)` still runs on view appearance; `DashboardViewModel.reload(events:)` had no input-key skip.
3. Full refresh/ledger pressure contributes to launch-time work. Partially confirmed from earlier disk-write diagnostic, but current HEAD already has ledger persistence batching.
4. Pure SwiftUI layout contributes. Process sample while idle showed the main thread mostly in SwiftUI layout, not obvious synchronous parsing.

Fixes applied:

- `SessionsOverviewDetailView` now builds one `OverviewSnapshot` per body pass and passes the summary/project/recent/cache values through the cards and sections.
- `DashboardViewModel` now tracks a reload input key (`period`, `lastRefreshedAt`, `reloadToken`, event count) so repeated Dashboard openings with unchanged data skip the detached aggregate.
- `DashboardView` now calls `reloadIfNeeded(events:storeRefreshedAt:)`.
