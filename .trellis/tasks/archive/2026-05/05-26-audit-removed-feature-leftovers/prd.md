# brainstorm: audit removed feature leftovers

## Goal

Audit the current codebase for feature-removal leftovers from the cleanup work done between 2026-05-25 and 2026-05-26, especially cases where UI or stores still expose data produced by removed features.

## What I already know

* The user removed many features from 2026-05-25 to 2026-05-26 and suspects there are leftovers in session detail.
* The session detail leftover is backed by a removed analysis store even though its user-facing feature was removed.
* Recent cleanup commits include Dictionary removal, deprecated feature cleanup, release-build residual fixes, removed feature-module cleanup, and API-provider switcher removal.
* Confirmed strong residual: Sessions still has a removed analysis destination, sidebar row, detail view, visualization view, store/service/model/index, tokenizer bridge/resource copy, and tests.
* Confirmed build residual: a removed desktop automation dependency is still declared as an app dependency/target in `project.yml`, but current product Swift code no longer references it outside release history.
* Confirmed asset residual: provider assets for removed providers remain in `Assets.xcassets/Providers`; current `ProviderKind` only references `codex-logo` and `codex`.
* Confirmed by user for removal: old editable profile support should be deleted as residue; the visible Configs page should stay read-only if retained.
* Mostly clean: removed community/cloud/debugging/module/switcher/provider implementation code no longer has active Swift references outside generated release history or docs.

## Assumptions (temporary)

* Scope is confirmed. Implementation should delete the identified leftovers rather than hiding them.
* A leftover means at least one of: navigation entry remains, visible UI remains, AppEnvironment/store/view model remains, model/service/test/resource remains, generated release notes mention is harmless unless it affects UI.

## Open Questions

* Answered: remove entire leftover feature slices including tests, models, services, storage paths, project references, build resources, and assets. Do not keep old feature names in app code solely for one-off legacy cache deletion.

## Requirements (evolving)

* Identify feature slices removed or partially removed in the 2026-05-25 to 2026-05-26 cleanup window.
* For each feature slice, check current-code leftovers across UI, navigation, stores/view models, services, models, tests, project references, resources, and persistent data cleanup.
* Produce a concise evidence-backed residual-risk list before any implementation.
* If implementation proceeds, remove the selected feature slices consistently across navigation, UI, environment composition, stores/services/models, tests, build configuration, assets/resources, and localization.
* Remove all identified leftovers: removed session analysis stack, tokenizer integration, removed desktop automation build target/dependency, old provider assets, and old profile editing/apply-backup support.

## Acceptance Criteria (evolving)

* [x] Audit identifies confirmed leftovers with file references.
* [x] Audit separates harmless historical/generated references from active product code.
* [x] Audit highlights likely compile/runtime risks if leftovers are removed.
* [x] User confirms cleanup scope before implementation.
* [x] Removed active removed-analysis session UI and store wiring.
* [x] Removed removed-analysis models, services, view models, views, tests, tokenizer bridge/resources, project references, and submodule metadata.
* [x] Removed desktop automation target/dependency/source tree and old removed-provider assets.
* [x] Removed profile editor support while keeping read-only AI Config preview.
* [x] Scrubbed visible release-history wording for removed feature names.

## Definition of Done (team quality bar)

* Tests added/updated if implementation changes code.
* `bash scripts/run-tests.sh` and `bash scripts/run-debug.sh` run after code changes.
* Docs/notes updated if behavior changes.
* Rollout/rollback considered if risky.

## Out of Scope (explicit)

* No unrelated feature rewrites outside the confirmed leftover cleanup scope.
* No release packaging/signing changes unless cleanup touches release-only code.

## Technical Notes

* Current branch at task creation: `codex/release-ci-fix`.
* Current workspace has pre-existing uncommitted changes in models, provider parser/store files, `.codex/`, `.serena/`, and a Python cache file.
* Active residual references found:
  * Removed session analysis UI, routing, store, services, models, tests, bridge files, and build references were present before this cleanup.
  * `project.yml` still declared and linked a removed desktop automation dependency, but no active Swift code imported it.
  * `ClaudeStats/Assets.xcassets/Providers/` still contains assets for removed providers besides Codex.
  * Old feature cache paths no longer have app read/write code. The app does not keep deleted feature names solely to perform one-off cache cleanup.

## Verification Notes

* `bash scripts/generate.sh` succeeded.
* `python3 -B -m unittest discover scripts/tests` passed: 22 tests.
* `rg` over app code, tests, `project.yml`, `.gitmodules`, README, release notes, Trellis package config/specs, and generated Xcode project found no active hits for removed analysis, tokenizer, desktop automation, profile editor, or old removed provider names.
* `bash scripts/run-tests.sh` and `bash scripts/run-debug.sh` both reached Xcode build/launch and then stopped because this machine's active developer directory is `/Library/Developer/CommandLineTools`, not a full Xcode install.
