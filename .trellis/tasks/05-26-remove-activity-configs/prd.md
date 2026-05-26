# 删除“操作 / Ops”功能

## Goal

Remove only the Ops feature from Claude Stats so the main window and app runtime no longer carry UI or code paths for the Brew / Environment operations surface.

## What I already know

* The user clarified the final scope: only delete the `操作 / Ops` feature.
* Activity, AI Activity Analysis, Configs, Git, Settings, Dashboard, Usage, and Sessions stay in scope as existing features.
* Ops is currently wired into `SidebarColumn`, `MainWindowView`, `MainWindowModeShell`, and `AppEnvironment`.
* Ops has dedicated models, service/command runner, view model, views, and tests:
  * `ClaudeStats/Models/Ops/OpsModels.swift`
  * `ClaudeStats/Services/Ops/OpsCommandRunner.swift`
  * `ClaudeStats/Services/Ops/OpsService.swift`
  * `ClaudeStats/ViewModels/OpsStore.swift`
  * `ClaudeStats/Views/MainWindow/Ops/*`
  * `ClaudeStatsTests/OpsTests.swift`

## Requirements

* Remove the Ops row from the main sidebar.
* Remove `MainWindowMode.ops` and all Ops sidebar/detail wiring from the main window shell.
* Remove `OpsStore` from `AppEnvironment`.
* Delete Ops-only model, service, command runner, view model, view, preview, and test files.
* Remove only localization keys that exclusively serve Ops.
* Preserve Activity, AI Activity Analysis, Configs, Git, Settings, Dashboard, Usage, Sessions, and unrelated `ops` wording in comments or release history.

## Acceptance Criteria

* [ ] The main sidebar no longer shows Ops / 操作.
* [ ] No code references removed Ops-only types such as `OpsStore`, `OpsSection`, `OpsService`, `OpsCommandInvocation`, `OpsSidebarColumn`, or `OpsDetailView`.
* [ ] `MainWindowMode` no longer contains `.ops`.
* [ ] Activity and Configs code remains present and wired.
* [ ] `bash scripts/run-tests.sh` passes.
* [ ] `bash scripts/run-debug.sh` builds and launches the app from the canonical DerivedData path.

## Definition of Done

* Tests updated by removing Ops tests.
* Build and test commands pass for the affected app.
* `bash scripts/run-debug.sh` compiles and launches the latest app, per project guide.
* Diff review confirms no dead Ops navigation state, runtime object, or orphaned source files remain.

## Out of Scope

* Removing Activity or AI Activity Analysis.
* Removing Configs.
* Removing Git activity / Git Tracking.
* Moving Brew or Environment checks into another page.
* Adding replacement UI for Ops.

## Technical Notes

* Relevant navigation files inspected:
  * `ClaudeStats/Views/MainWindow/SidebarColumn.swift`
  * `ClaudeStats/Views/MainWindow/MainWindowView.swift`
  * `ClaudeStats/Views/MainWindow/MainWindowModeShell.swift`
* `AppEnvironment` currently constructs `OpsStore`; that must be removed with its constructor injection point.
* `SceneStorage("mainWindow.opsSection")` can be deleted without migration because it is only transient UI state.
