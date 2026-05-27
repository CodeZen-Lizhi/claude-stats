# Session Deletion Data Flow Research

## Relevant Current Data Flow

* `SessionStore.refresh()` discovers provider sessions, parses changed transcripts, writes/updates `UsageLedgerStore`, builds the visible session graph, then snapshots ledger events into `usageEventsSnapshot`.
* `SessionStore.sessions` is not the only source of stats. `SessionStore.summary(...)`, Usage page, menu-bar usage, and Dashboard all read ledger-backed `UsageLedgerEvent` data.
* Existing behavior intentionally preserves usage history when transcript files disappear: `SessionStoreTests.deletedTranscriptDoesNotRemoveLedgerTotals` asserts that sessions vanish but ledger totals remain.
* Dashboard main window currently calls `env.store.usageEventsSnapshot()`, so it will keep showing usage unless ledger events are filtered/cleared.
* Usage view calls `store.summary(...)`, which reads `usageEventsSnapshot`; same implication as Dashboard.
* Git activity overview uses visible `sessions` for repo cwd discovery and correlation. Commit inspector uses visible `sessions` and merged session stats for AI usage attribution.
* Codex subagent sessions are represented as `SessionAgentInfo` and folded into parent sessions by `SessionStore.buildSessionGraph(...)`. Parent stats are merged with child stats via `mergedStats(...)`.
* Ledger events store both `sessionID` and optional `parentSessionID`; child events can still affect aggregate usage after graph folding.

## Implications

* Directly deleting transcript files is insufficient and currently conflicts with the ledger preservation contract.
* A clean delete needs one central exclusion/tombstone mechanism applied before:
  * visible `sessions` are assigned,
  * parent/child graph folding happens,
  * ledger events are exposed through `usageEventsSnapshot` / `summary(...)`,
  * Git workspace cwd discovery and attribution run.
* Deleting a visible parent session should include all folded child session ids, otherwise child usage can remain in ledger summaries or reappear as unresolved agent sessions.
* Deleting a child/subagent session should remove that child from the parent aggregate stats and ledger events, while keeping the parent session visible.
* The raw project directory, Git repo, Codex config directory, and unrelated transcript files should not be touched by default.

## Recommended MVP Shape

Use a soft-delete/tombstone store in the app support directory. Persist deleted session ids plus provider/source path metadata. On refresh, filter discovered sessions and ledger events through the tombstone set. Add an optional destructive "delete transcript file too" later only if users explicitly want disk cleanup.
