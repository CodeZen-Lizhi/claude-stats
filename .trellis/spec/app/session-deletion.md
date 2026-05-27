# Session Deletion Contract

## Scenario: Delete transcript content while preserving historical stats

### 1. Scope / Trigger

- Applies when adding or changing session deletion, deleted-session metadata, usage ledger retention, Dashboard/Usage summaries, menu-bar totals, or Git attribution based on session history.
- Trigger: deleting a session touches UI, `SessionStore`, filesystem storage, ledger history, and Git consumers.

### 2. Signatures

- `SessionStore.deleteSession(_ session: Session) async -> SessionDeletionResult`
- `SessionStore.deleteSessions(_ sessions: [Session]) async -> SessionDeletionResult`
- `DeletedSessionRecord(session:deletedAt:)`
- `DeletedSessionStore.records() -> [DeletedSessionRecord]`
- `DeletedSessionStore.add(_:) throws`
- `DeletedSessionStore.remove(sessionIDs:) throws`

### 3. Contracts

- Delete moves the original transcript file to the macOS Trash via `FileManager.trashItem`.
- Delete must not delete project directories, Git repositories, Codex config directories, or unrelated transcript files.
- Delete must not remove or filter `UsageLedgerEvent` records.
- `DeletedSessionRecord` must contain only non-conversation metadata needed for history: session id, provider, project/cwd, transcript source path, timestamps, source kind, file size, and parent/child agent relationship metadata.
- Visible session lists consume live discovered sessions filtered by deleted records.
- Git attribution consumes live sessions plus deleted-session metadata so repo sources and commit AI usage survive transcript deletion.

### 4. Validation & Error Matrix

- Deleted-record write fails -> do not move the transcript, return a failure.
- Trash move fails -> remove the deleted record if it was written, return a failure, keep the session visible.
- Partial batch failure -> successful sessions stay deleted; failed sessions remain visible; do not roll back successes.
- Deleted parent session -> include folded child sessions in deletion targets, and keep parent/child metadata for historical attribution.
- Deleted child session -> hide the child transcript, keep parent session and historical usage.

### 5. Good/Base/Bad Cases

- Good: delete a session, source path disappears, `summary(.allTime)` totals remain unchanged, Git history still sees the repo.
- Base: batch delete two sessions where one trash move fails; result has one deleted id and one failure.
- Bad: filtering ledger events by deleted session id, which makes Dashboard, Usage, menu-bar totals, or Commit Inspector history drop after deletion.

### 6. Tests Required

- Single delete hides the session, records a trash move, and preserves ledger totals.
- Batch delete keeps failures visible while successes stay hidden.
- Deleted parent hides folded child sessions and preserves historical parent/child attribution after refresh/restart.
- Deleted last repo session still appears in Git attribution inputs.
- Localizable delete/selection strings exist for Chinese.

### 7. Wrong vs Correct

#### Wrong

```swift
sessions = sessions.filter { !deletedIDs.contains($0.id) }
usageEventsSnapshot = usageEventsSnapshot.filter { !deletedIDs.contains($0.sessionID) }
```

#### Correct

```swift
sessions = visibleSessions
historicalSessions = liveSessions + deletedSessionMetadata
usageEventsSnapshot = await usageLedger.events()
```
