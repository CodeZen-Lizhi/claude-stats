# brainstorm: remove activity and configs

## Goal

Remove the AI Activity feature and the Configs feature from Claude Stats so the main window, Settings, provider contracts, services, models, localization, and tests no longer carry UI or code paths for those removed surfaces.

## What I already know

* The user wants to delete the Activity sidebar/page and remove AI Activity Analysis from Settings > Tracking.
* The user wants to delete the Configs feature shown under Tools.
* Activity is currently controlled by `Preferences.aiActivityAnalysisEnabled` and appears in the main sidebar only when enabled.
* Activity code includes main-window activity views, the legacy/share `AIActivityView`, `AIActivityViewModel`, `ScreenTimeService`, `ActivityAnalyzer`, `ActivitySurfaceCatalog`, `DayActivity`, `AppFocusInterval`, and related tests.
* Settings > Features still has an `AI Activity Analysis` feature card and Settings > Tracking still has the AI Activity Analysis group.
* Configs is still wired into `MainWindowMode.configs`, `MainWindowView.openConfigs()`, `SidebarColumn`, `MainWindowModeShell`, and the `ClaudeStats/Views/MainWindow/Configs/` view folder.
* Configs is not only UI: `AppEnvironment` constructs `AIConfigsViewModel`, `AIConfigScanner` scans provider-owned sources, and `Provider`/`CodexProvider` expose AI config source APIs.
* Configs tests include `AIConfigScannerTests` and `AIConfigsViewModelTests`.

## Assumptions (temporary)

* "Delete related all code" for Activity means removing the feature from product behavior, settings, preferences, services, tests, previews, and share/export paths.
* "Delete Configs feature" means full removal of the Configs product surface and its dedicated scanner/model/viewmodel infrastructure, not merely hiding the sidebar item.
* General usage/dashboard "activity" wording that refers to session activity or git activity should remain unless it depends on the removed AI Activity page.
* Git Tracking should remain in Settings > Tracking.
* Ops should remain in Tools.

## Open Questions

* None.

## Requirements (evolving)

* Remove Activity from the main sidebar and `MainPage`.
* Remove AI Activity Analysis from Settings > Features and Settings > Tracking.
* Remove activity-specific preferences, Screen Time access checks, coding surface/CLI host configuration, and related persistence keys if no longer used.
* Remove Activity page views, view model, analyzer/service/model code, and tests that only exist for AI Activity Analysis.
* Remove Configs from the main sidebar and main-window mode shell.
* Remove Configs views, view model, scanner, models, tests, and provider config-source contracts.
* Preserve unrelated concepts named activity: session activity timestamps, git activity, dashboard heatmap activity, release notes, and system monitor activity.

## Acceptance Criteria (evolving)

* [x] The main sidebar no longer shows Activity.
* [x] Settings no longer shows AI Activity Analysis controls or Screen Time/coding surface configuration.
* [x] The main sidebar no longer shows Configs.
* [x] No code references removed Activity-only types such as `AIActivityViewModel`, `ScreenTimeService`, `ActivityAnalyzer`, `ActivitySurfaceCatalog`, `DayActivity`, or `AppFocusInterval`.
* [x] No code references removed Configs-only types such as `AIConfigsViewModel`, `AIConfigScanner`, or `AIConfigsSection` if full deletion is chosen.
* [ ] The app builds and tests after deletion.
  * Script tests pass, but Xcode build/test is blocked locally because `xcode-select -p` points to `/Library/Developer/CommandLineTools` and no `Xcode*.app` exists under `/Applications`.
* [ ] The canonical debug run succeeds via `bash scripts/run-debug.sh`.
  * Blocked by the same missing full Xcode environment; `xcodebuild` reports that the active developer directory is CommandLineTools.

## Definition of Done

* Tests added/updated/removed to match the deleted behavior.
* Build and test commands pass for the affected app.
* `bash scripts/run-debug.sh` compiles and launches the latest app, per project guide.
* Diff review confirms no hidden fallback, dead navigation state, stale settings rows, or orphaned localization keys for the removed surfaces.

## Out of Scope

* Removing Git activity / Git Tracking.
* Removing dashboard or session usage activity concepts.
* Removing Ops.
* Redesigning the remaining Settings layout beyond closing gaps left by deleted cards/groups.
* Changing provider transcript parsing or usage accounting except where needed to remove Configs contracts.

## Technical Notes

* Relevant navigation files inspected:
  * `ClaudeStats/Views/MainWindow/SidebarColumn.swift`
  * `ClaudeStats/Views/MainWindow/MainWindowView.swift`
  * `ClaudeStats/Views/MainWindow/MainWindowModeShell.swift`
* Activity files found:
  * `ClaudeStats/ViewModels/AIActivityViewModel.swift`
  * `ClaudeStats/Services/ScreenTimeService.swift`
  * `ClaudeStats/Services/ActivityAnalyzer.swift`
  * `ClaudeStats/Services/ActivitySurfaceCatalog.swift`
  * `ClaudeStats/Models/DayActivity.swift`
  * `ClaudeStats/Models/AppFocusInterval.swift`
  * `ClaudeStats/Views/MainWindow/Activity/*`
  * `ClaudeStats/Views/Activity/AIActivityView.swift`
  * `ClaudeStatsTests/AIActivityViewModelTests.swift`
  * `ClaudeStatsTests/ActivityAnalyzerTests.swift`
  * `ClaudeStatsTests/ActivitySurfaceCatalogTests.swift`
* Configs files found:
  * `ClaudeStats/Models/AIConfigs/AIConfigModels.swift`
  * `ClaudeStats/Services/AIConfigs/AIConfigScanner.swift`
  * `ClaudeStats/ViewModels/AIConfigsViewModel.swift`
  * `ClaudeStats/Views/MainWindow/Configs/*`
  * `ClaudeStatsTests/AIConfigScannerTests.swift`
  * `ClaudeStatsTests/AIConfigsViewModelTests.swift`
* Provider config-source APIs are currently in `ClaudeStats/Providers/Provider.swift` and implemented by `ClaudeStats/Providers/Codex/CodexProvider.swift`.
* `AppEnvironment` currently constructs `AIConfigsViewModel`, so full Configs removal must update the composition root.
* `ShareExportView` currently has an Activity export path, so Activity deletion must remove that pane option/data path.

## Decision (ADR-lite)

**Context**: Configs can be hidden at the sidebar only, but its scanner, view model, model types, provider hooks, and tests would remain as dead product code.

**Decision**: Fully delete Configs: remove the sidebar entry, `.configs` main-window mode, `AIConfigsViewModel`, `AIConfigScanner`, `AIConfigModels`, related views/tests, and `Provider` / `CodexProvider` config-source APIs.

**Consequences**: This produces a larger diff but prevents unused scanner contracts and product state from lingering after the UI is removed.
