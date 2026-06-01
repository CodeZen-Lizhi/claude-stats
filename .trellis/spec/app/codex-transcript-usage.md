# Codex Transcript Usage Contract

## Scenario: Do not count forked transcript replay history as new usage

### 1. Scope / Trigger

- Applies when changing `CodexTranscriptParser`, `UsageLedgerParseState`, `UsageLedgerStore`, `SessionStore.refresh()`, or usage summaries backed by Codex transcript `token_count` events.
- Trigger: Codex Desktop can create a forked/resumed transcript whose first `session_meta` has `forked_from_id`, then copy parent-session history into the new file with the fork file's outer line timestamp.

### 2. Signatures

- `CodexTranscriptParser.parse(transcriptAt:fallbackTitle:sessionID:) -> SessionStats?`
- `CodexTranscriptParser.parseUsageAppend(_:from:) -> UsageLedgerAppendResult?`
- `UsageLedgerParseState.currentParserRevision`
- `UsageLedgerParseState.parserRevision`
- `SessionStore.canRestoreFromLedger(_:state:)`
- `SessionStore.canAppendUsage(_:state:)`

### 3. Contracts

- `event_msg` / `token_count` is the only Codex transcript event that creates billable usage records.
- For ordinary transcripts, every `token_count.info.last_token_usage` with positive total usage is eligible for parsing.
- For forked transcripts, detect a first-line `session_meta` payload with `forked_from_id`.
- In a forked transcript, skip `token_count` records whose outer line timestamp falls inside the fork creation second. Those records are copied parent history, not new API requests.
- Incremental append parsing must count a complete final JSONL record even when the writer has not emitted a trailing newline yet; only malformed/incomplete final records should remain unadvanced for the next scan.
- Use a parser revision when changing usage semantics so old persisted parse states rebuild instead of restoring polluted ledger events by file size and mtime alone.

### 4. Validation & Error Matrix

- Missing `forked_from_id` -> parse first-second `token_count` normally.
- `forked_from_id` present and `token_count` is in the fork creation second -> skip that usage event.
- `forked_from_id` present and `token_count` timestamp is later than the fork creation second -> count normally.
- Complete trailing `token_count` JSON without a newline -> count it and advance the parsed byte offset.
- Incomplete trailing JSON -> do not count it and do not advance past it.
- Old `UsageLedgerParseState.parserRevision == nil` or stale -> rebuild from transcript, do not append or restore.
- Missing or malformed `token_count.info.last_token_usage` -> skip that usage event as before.

### 5. Good/Base/Bad Cases

- Good: a forked transcript replays 156 parent `token_count` records at the fork creation second; the parser emits zero usage events for that replay block and counts later live events.
- Base: a non-forked transcript has a first-second `token_count`; the parser counts it.
- Bad: using the outer line timestamp from copied parent history and adding replayed `token_count` records to today's ledger.

### 6. Tests Required

- Parser test: forked transcript skips replay `token_count` events from the fork creation second and counts later usage.
- Parser test: non-forked transcript keeps first-second usage.
- Append parser test: complete final JSONL line without a newline is counted, while incomplete final JSON remains pending.
- Store/planning behavior: parser revision changes cause stale states to rebuild before restoring/appending usage.
- Regression data check when available: affected hour should no longer contain the fork replay request spike.

### 7. Wrong vs Correct

#### Wrong

```swift
case ("event_msg", "token_count"):
    let usage = payload.info?.lastTokenUsage?.tokenUsage
    // Counts copied parent history in forked transcripts.
```

#### Correct

```swift
case ("event_msg", "token_count"):
    guard !replayFilter.shouldSkipTokenCount(line: line, date: date) else { break }
    let usage = payload.info?.lastTokenUsage?.tokenUsage
```
