# Remove API Provider Switcher

## Goal

Remove the API Provider Switcher feature so the app behaves as if this provider-management UI and its stored-provider library never existed. Claude Stats should keep the Codex-only product model and continue to read configuration files through the existing Configs workspace.

## What I already know

* The user explicitly wants the screenshot feature deleted, not merely hidden.
* Current screenshots show the stale "API 服务商切换器" page and sidebar "切换器" entry.
* Repo inspection found the feature across UI, view model, persistence/service code, tests, preferences, and localization strings.
* The app already has a separate Configs workspace (`AIConfigs*`) that scans and reads config files directly; that should remain.

## Requirements

* Remove the API Provider Switcher page from the main window and source tree.
* Remove provider-management models, view model, secret store, and persistence store used only by the switcher.
* Remove switcher-specific preferences and settings UI.
* Remove switcher-specific tests and localization strings.
* Preserve the existing Configs workspace that directly reads configuration files.
* Keep Codex-only provider behavior intact.

## Acceptance Criteria

* [x] No sidebar or page shows "API Provider Switcher" / "切换器".
* [x] No app code references `APIProviderSwitcherViewModel`, `ConfigurationProviderStore`, or `ConfigurationsView`.
* [x] No tests target the deleted switcher behavior.
* [x] Configs workspace remains available from the sidebar and still uses `AIConfigs*`.
* [x] Project tests/build are run where local tooling allows; any environment blocker is documented.

## Definition of Done

* Tests added/updated or removed to match deleted behavior.
* Lint/typecheck/build checks run where possible.
* Docs/PRD reflect that the feature is removed.
* Rollback is straightforward via git revert if needed.

## Out of Scope

* Removing the Codex provider itself.
* Removing the direct configuration-file browser/editor under Configs.
* Reworking provider registry architecture beyond deleting this stale switcher.

## Technical Notes

* Main UI files: `ClaudeStats/Views/MainWindow/MainWindowView.swift`, `ClaudeStats/Views/MainWindow/SidebarColumn.swift`.
* Switcher-only code found in `ClaudeStats/Views/MainWindow/Configurations/ConfigurationsView.swift`, `ClaudeStats/ViewModels/APIProviderSwitcherViewModel.swift`, `ClaudeStats/Services/ConfigurationProviderStore.swift`, `ClaudeStats/Services/APIProviderSecretStore.swift`, `ClaudeStats/Models/Configurations/APIProviderModels.swift`.
* `CLIEnvironmentChecker` was switcher-only after inspection and was deleted with the switcher UI.
* `bash scripts/generate.sh` passed.
* `bash scripts/run-tests.sh` passed its Python tests, then stopped at `xcodebuild` because `xcode-select` points to `/Library/Developer/CommandLineTools`.
* `bash scripts/run-debug.sh` stopped at the same `xcodebuild` environment blocker.
