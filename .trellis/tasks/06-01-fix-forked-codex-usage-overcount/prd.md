# Fix Forked Codex Usage Overcount

## Goal

Fix the Codex usage aggregation bug where forked/resumed transcript files replay parent-session history with a new outer timestamp, causing Claude Stats to count historical `token_count` records as today's real requests. The corrected stats should align with the trusted Aether relay request ledger for request count and token totals.

## What I Already Know

* The user compared Claude Stats against the Aether relay dashboard and confirmed the relay request count is the source of truth.
* Claude Stats reads local Codex transcripts from `~/.codex/sessions` and persists aggregate usage in `~/Library/Application Support/Codex Statistics/UsageLedger/usage-ledger.json`.
* Aether Postgres showed the 09:00 hour had 212 real `AI INPUT` usage records, while Claude Stats counted 362 local `token_count` events.
* The excess came from `~/.codex/sessions/2026/06/01/rollout-2026-06-01T09-17-41-019e80c2-0b9f-77a3-90ca-c62cb82a0d29.jsonl`.
* That transcript starts with `forked_from_id: 019e731d-8d2c-7813-83f6-f5e902d17355` and then replays parent-session history.
* Its first second (`2026-06-01T01:17:41Z`) contains 156 replayed `token_count` records totaling about 19.44M tokens: 1.15M input, 73.28K output, and 18.22M cache read.
* Current parser logic in `CodexTranscriptParser` uses the outer line timestamp for every `token_count`, so replayed parent history is attributed to the fork creation time.

## Assumptions

* A forked transcript's initial burst of replayed history should not be counted again if the parent session already owns those usage records.
* Real usage after the fork starts once the copied parent-history prelude ends and normal event timestamps advance beyond the fork-creation replay burst.
* The fix should preserve legitimate usage in ordinary non-forked transcripts.

## Open Questions

* None.

## Requirements

* Detect forked Codex transcripts that contain replayed parent-session history.
* Prevent replayed parent `token_count` events from being added as new billable ledger events.
* Avoid deleting or undercounting genuine post-fork token events.
* Ensure existing ledger data can be corrected by a rescan/rebuild path or by making parsing deterministic enough that clearing/replacing session events produces correct totals.

## Acceptance Criteria

* [ ] The problematic fork transcript no longer contributes the 156 replayed `09:17:41` token events as new usage.
* [ ] Today's Claude Stats totals for the affected hour move toward the Aether ledger baseline instead of retaining the 150+ request overcount.
* [ ] Non-forked transcripts still parse their `token_count` events normally.
* [ ] Tests cover forked transcript replay history and ordinary transcript parsing.
* [ ] Project build/test command passes.

## Definition of Done

* Tests added or updated for the parser behavior.
* `bash scripts/run-tests.sh` passes.
* `bash scripts/run-debug.sh` passes, per project guide.
* Review confirms no unrelated files or user changes were reverted.
* Rollback is straightforward: revert the parser/test changes.

## Out of Scope

* Changing Aether relay counting logic.
* Repricing model rates.
* Adjusting output token display to exclude `reasoning_output_tokens`.
* Broad redesign of the Usage Ledger storage layer unless required for a safe migration.

## Technical Notes

* New executable contract captured in `.trellis/spec/app/codex-transcript-usage.md`.
* Likely implementation area: `ClaudeStats/Providers/Codex/CodexTranscriptParser.swift`.
* Aggregate display path: `ClaudeStats/Models/UsageSummary.swift`.
* Ledger persistence path: `ClaudeStats/Services/UsageLedgerStore.swift`.
* Codex path discovery: `ClaudeStats/Providers/Codex/CodexPaths.swift` and `CodexSessionScanner.swift`.
* Relevant behavior: `UsageSummary.make(period:events:)` treats ledger events as aggregate truth and uses event count as request count.
* The forked transcript has an outer `session_meta` with `forked_from_id`, followed by copied parent session records whose outer line timestamps are rewritten to the fork creation second.

## Technical Approach

Investigate the parser seam and add a replay-history guard for forked transcripts. Prefer a narrow parser-level fix that avoids emitting `UsageLedgerEvent` records for copied parent history, then add a regression fixture that mimics a forked transcript prelude followed by genuine post-fork token usage.

## Decision (ADR-lite)

**Context**: Codex fork/resume transcripts can include copied parent-session history with new outer timestamps, but Aether's request ledger confirms those copied entries are not new API requests.

**Decision**: Fix only the fork/resume history replay overcount. Do not change reasoning-token display semantics in this task.

**Consequences**: A parser-level fix should correct future scans and make rebuilds deterministic, but existing persisted ledger data may need a rescan/replace path if already polluted. Relay UI parity for reasoning output remains out of scope.
