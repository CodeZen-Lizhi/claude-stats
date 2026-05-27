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

## Scenario: Refresh usage ledger without write amplification

### 1. Scope / Trigger

- Applies when changing `UsageLedgerStore`, `SessionStore.refresh()`, usage-ledger parse state, or any refresh path that persists historical usage.
- Trigger: the ledger is a whole-file JSON snapshot, so every `persist()` rewrites all usage events and parse states.

### 2. Signatures

- `UsageLedgerStore.beginPersistenceBatch()`
- `UsageLedgerStore.endPersistenceBatch()`
- `UsageLedgerStore.markSeen(_ sessions: [Session], now: Date) async`
- `SessionStore.refresh() async`
- `AppLifecyclePolicy.reassertAutomaticTerminationPolicy()`

### 3. Contracts

- A single refresh should coalesce multiple ledger mutations into one final write where possible.
- `markSeen` must persist only when a parse state's source existence changes; an unchanged live session must not rewrite the ledger just to advance `lastSeenAt`.
- Deleted transcript handling must still preserve `UsageLedgerEvent` history.

### 4. Validation & Error Matrix

- Unchanged refresh -> no ledger rewrite.
- New/appended/rewritten transcript -> update in-memory ledger and flush once at the end of the refresh batch.
- Persist failure -> log through `Log.store.error`; do not silently drop visible in-memory refresh results.

### 5. Good/Base/Bad Cases

- Good: 200 parsed sessions in one refresh produce one final ledger write.
- Base: no transcript changes produce no ledger write.
- Bad: calling `persist()` after every parsed session, which rewrites the entire ledger hundreds of times.

### 6. Tests Required

- `markSeen` with unchanged live sessions keeps ledger file contents unchanged.
- Batched persistence defers writes during the batch and flushes the final snapshot when the batch ends.
- Existing deletion tests still prove usage totals survive transcript deletion.
- Lifecycle tests prove the resident menu-bar app can reassert automatic-termination disablement after activation-policy changes.

### 7. Wrong vs Correct

#### Wrong

```swift
for await result in group {
    await usageLedger.replaceEvents(for: session, stats: stats)
}
```

#### Correct

```swift
await usageLedger.beginPersistenceBatch()
for await result in group {
    await usageLedger.replaceEvents(for: session, stats: stats)
}
await usageLedger.endPersistenceBatch()
```

## Scenario: Keep usage aggregates out of repeated SwiftUI body work

### 1. Scope / Trigger

- Applies when Dashboard, Usage, Sessions overview, menu-bar labels, or cards render `UsageSummary`, `SessionStats`, heatmaps, or per-model breakdowns.
- Trigger: SwiftUI may evaluate computed view properties multiple times per render pass, and layout containers such as `ViewThatFits` can evaluate alternate branches.

### 2. Signatures

- `UsageSummary.make(period:sessions:pricing:now:calendar:)`
- `UsageSummary.make(period:events:now:calendar:)`
- `DashboardViewModel.reloadIfNeeded(events:storeRefreshedAt:)`
- `SessionsOverviewDetailView.makeSnapshot()`

### 3. Contracts

- Build expensive per-page aggregates once per render pass or off-main in a view model.
- Reopening a page with the same store refresh timestamp and period should reuse the existing view-model result.
- Cards, tables, and charts in one page should share the same aggregate snapshot rather than each calling `UsageSummary.make(...)`.

### 4. Validation & Error Matrix

- Same page reopened, same store refresh -> skip Dashboard aggregate reload.
- Same Sessions overview body pass -> one `UsageSummary` snapshot feeds all stats cards and model table.
- Store refresh or period change -> recompute aggregates.

### 5. Good/Base/Bad Cases

- Good: `let snapshot = makeSnapshot()` then pass `snapshot.summary` to every section.
- Base: Dashboard reload runs after `SessionStore.lastRefreshedAt` changes.
- Bad: a computed `summary` property that calls `UsageSummary.make(...)` and is read separately by each card.

### 6. Tests Required

- Prefer pure view-model tests for reload-skip behavior when the seam is available.
- For view-only snapshot refactors, verify with build/type-check and keep the aggregate call visibly centralized.

### 7. Wrong vs Correct

#### Wrong

```swift
private var summary: UsageSummary {
    UsageSummary.make(period: .allTime, sessions: sessions, pricing: pricing)
}
```

#### Correct

```swift
let snapshot = makeSnapshot()
statsGrid(snapshot)
modelBreakdown(snapshot)
```
