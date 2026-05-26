# Diagnose packaged app background exit

## Problem

The installed `/Applications/Claude Stats.app` can disappear from the user's perspective even though it was expected to keep running as a menu-bar app.

Observed evidence from system logs on 2026-05-25:

- Installed app version: `1.7.6 (75)`, bundle id `com.claudestats.ClaudeStats`, `LSUIElement=1`.
- No matching crash reports were found in `~/Library/Logs/DiagnosticReports`.
- `loginwindow` recorded `applicationQuit` events for `Claude Stats`.
- AppKit logs repeatedly toggled `_kLSApplicationWouldBeTerminatedByTALKey`, including `Setting ...=1`, which means the app was considered eligible for macOS Automatic Termination.
- The app is a menu-bar-only app, so it must remain resident even when no standard window is open.

## Goal

Prevent macOS Automatic Termination from reclaiming Claude Stats while it is meant to run as a resident menu-bar app.

## Scope

- Add a small, testable lifecycle policy for disabling Automatic Termination.
- Apply it during app launch.
- Add a regression test for the lifecycle contract.
- Verify with tests and the canonical debug run script.

## Non-goals

- Do not change Sparkle update behavior unless evidence later points there.
- Do not modify Atoll or packaging flow unless required by verification.
- Do not touch unrelated dirty worktree changes.

## Acceptance

- A focused test proves the app requests Automatic Termination suppression with a resident menu-bar reason.
- `bash scripts/run-tests.sh` passes, or any failure is clearly unrelated and documented.
- `bash scripts/run-debug.sh` builds and launches the app from `/tmp/Codex-stats-build`.
