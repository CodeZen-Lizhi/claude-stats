# Remove Dictionary Feature

## Goal

Remove the Dictionary / Technical Terms feature from this fork because this project does not need user-managed transcript terminology. Future upstream changes in this area should not be carried into this fork unless explicitly requested.

## What I Already Know

* The user asked to remove the feature, related code, page, and documentation.
* Dictionary currently means the removed technical-term management feature.
* The settings page is exposed as `Dictionary` and backed by `TechnicalTermDictionaryStore`.
* The product PRD exists at `docs/claude-stats-product-prd.md`.

## Assumptions

* User-managed built-in/global/project term dictionary management should be removed.

## Requirements

* Remove the Dictionary settings page and sidebar entry.
* Remove user-facing dictionary management models, store, repository, resources, and settings UI.
* Remove dictionary-specific wiring from the app environment.
* Remove documentation references that present Dictionary as a product/settings feature.
* Record in the product PRD that this fork intentionally does not include the Dictionary feature and should not follow upstream Dictionary changes by default.

## Acceptance Criteria

* [x] No Dictionary settings page is reachable from the app UI.
* [x] Dictionary management files and bundled technical term resources are removed.
* [x] Product PRD records the fork decision to omit Dictionary.
* [x] Search confirms no stale user-facing Dictionary feature references remain, aside from technical use of Swift `Dictionary`.
* [x] Project build/tests are run or an explicit blocker is recorded.

## Verification Notes

* `rg` confirms no stale Dictionary feature symbols remain in app/test/docs sources. Remaining dictionary hits are the task PRD and Swift standard `Dictionary`.
* A focused Swift typecheck for `SettingsSection.swift` passes with `L10n.swift`, confirming the settings enum itself is valid after removing the Dictionary case.
* Post-merge review on `12816a7 merge: codex-only provider cleanup` confirms the worktree merge did not reintroduce Dictionary. `docs/claude-stats-product-prd.md` still records the fork-specific Dictionary omission, and the merged product direction is now Codex-only.
* The worktree commit `e2af669 refactor: keep only Codex provider` is a broad provider-scope cleanup: it deletes non-Codex AI session providers, service-status and usage-limit bridge code, provider switcher UI, platform settings, and corresponding tests. It is orthogonal to Dictionary removal but reinforces that upstream multi-provider or Dictionary work should not be followed by default in this fork.
* `bash scripts/run-tests.sh` ran Python tests successfully (`Ran 22 tests ... OK`) but the full project test pipeline is blocked before Swift tests by local toolchain/environment issues:
  * Zig 0.15.2 cannot fetch Ghostty tarballs through the current proxy directly; `curl` can fetch the same URL and `zig fetch <local tarball>` was used to seed the cache for `uucode`.
  * After that, GhosttyKit build fails while linking Zig's build runner against the macOS 26 SDK with missing system symbols such as `_abort`, `_bzero`, `_dispatch_queue_create`, and `__availability_version_check`.
  * A temporary `xcrun` wrapper that redirects `macosx` SDK lookup to `macosx15.4` gets Zig past that linker failure, but Ghostty's XCFramework initialization still reaches iOS targets and fails with `DarwinSdkNotFound` because this machine only has CommandLineTools, not full Xcode/iOS SDKs.
  * Direct Xcode build is also blocked because `xcodebuild` requires full Xcode, while the active developer directory is `/Library/Developer/CommandLineTools`.
  * A direct `swiftc -typecheck` probe against the default macOS 26 SDK is also blocked by the local SDK/toolchain mismatch, so the focused probes above explicitly use `MacOSX15.4.sdk`.

## Definition of Done

* Code compiles.
* Relevant tests pass.
* Docs/PRD updated.
* Working tree only contains intentional changes for this removal plus pre-existing local files.

## Out of Scope

* Removing unrelated session views.
* Redesigning transcript analysis visualizations.
