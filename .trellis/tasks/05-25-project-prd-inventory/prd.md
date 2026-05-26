# Claude Stats Feature PRD Inventory

## Goal

Document the current Claude Stats product as a stable PRD reference for future refactors and feature work. The output should let a future developer understand what each module is for, what user-facing behavior exists today, and which parts are intentionally still incomplete.

## What I already know

* Claude Stats is a native macOS menu-bar app for AI coding work.
* The app reads local session, usage, status, Git, terminal, network, and configuration data.
* The current codebase already has major surfaces for sessions, stats, usage limits, activity, Git, configs, ops, system monitor, and settings.
* After `12816a7 merge: codex-only provider cleanup`, the main product boundary is Codex-only for AI session providers.
* Non-Codex provider code, provider UI, and provider-specific tests have been removed from `codex/dev`.
* The existing README describes the app as a focused macOS take on Claude Statistics and lists the major product areas.

## Assumptions

* This task is documentation-first, not a behavior change.
* The PRD should describe current behavior, not invent new product scope.
* The docs should be useful for future second-development and module-by-module refactoring.

## Requirements

* Create a repo-level PRD document that organizes current product behavior by feature family.
* Capture the functional scope of each major surface: menu bar, sessions, stats, usage limits, configuration, share cards, terminal, network debugging, Git, Notch Island, and settings.
* Preserve the distinction between shared behavior and provider-specific behavior.
* Record the Codex-only provider decision so future upstream sync work does not reintroduce removed AI session providers by default.
* Record known incomplete areas instead of hiding them.
* Add Trellis task context so future sub-agents can load relevant shared guidance.
* Keep the documentation readable as a reference for later feature work.

## Acceptance Criteria

* [ ] A repo-level product PRD exists under `docs/` and describes the current app by module and feature family.
* [ ] The Trellis task PRD explains the objective, known facts, assumptions, requirements, and acceptance criteria.
* [ ] `implement.jsonl` and `check.jsonl` contain real spec entries instead of only the seed example.
* [ ] The README points to the PRD/reference notes so the docs are easy to discover.
* [ ] The PRD reflects the current Codex-only provider boundary after the worktree merge.
* [ ] The resulting files are committed and pushed to the remote repository.

## Definition of Done

* Documentation is written in English and grounded in current repository reality.
* Trellis task metadata is populated with useful guidance files.
* The repository contains a durable reference for future feature work.
* Changes are committed and pushed.

## Out of Scope

* No product behavior changes.
* No refactors to the app runtime.
* No code generation or build-system changes.
* No attempt to fill unrelated bootstrap spec files in this task.

## Technical Notes

* Current repo README: `README.md`
* Reference notes: `docs/claude-statistics-inspiration-notes.md`
* Product PRD draft: `docs/claude-stats-product-prd.md`
* Trellis task directory: `.trellis/tasks/05-25-project-prd-inventory/`
* Worktree merge reviewed: `12816a7 merge: codex-only provider cleanup`
* Provider cleanup commit reviewed: `e2af669 refactor: keep only Codex provider`
