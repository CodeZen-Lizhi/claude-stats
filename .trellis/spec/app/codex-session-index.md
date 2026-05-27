# Codex Session Index Contract

## Scenario: Match Codex's user-facing session titles

### 1. Scope / Trigger

- Applies when changing Codex session discovery, session row titles, detail titles, parse caching, or visible session counts.
- Trigger: Codex stores the user-facing thread name outside transcript JSONL files, so transcript-derived titles can disagree with Codex's own sidebar.

### 2. Signatures

- `CodexPaths.sessionIndexFile -> URL`
- `CodexSessionScanner.readSessionTitleIndex(from:) -> [String: String]`
- `Session.titleOverride: String?`
- `SessionStats.applyingTitleOverride(_:) -> SessionStats`

### 3. Contracts

- The source file is `<CODEX_HOME>/session_index.jsonl`, where each line may contain `id` and `thread_name`.
- The index id is the raw Codex thread id, matching `Session.externalID`; the app's stable session id remains `codex::<id>`.
- Last valid index row wins for duplicate ids.
- `titleOverride` is display metadata and must win over transcript `thread_name_updated`, first user message, ad-hoc slug, project name, and UUID fallback.
- Usage events and token/cost accounting still come from transcripts and must not depend on `session_index.jsonl`.

### 4. Validation & Error Matrix

- Missing `session_index.jsonl` -> keep existing transcript-derived title behavior.
- Malformed index line -> skip that line only.
- Empty `id` or `thread_name` -> skip that line.
- Transcript exists but no index row -> keep transcript-derived title behavior.
- Index title changes while transcript bytes do not -> visible UI should still apply the new title override without requiring token reparse.

### 5. Good/Base/Bad Cases

- Good: transcript first user message is `我反馈一些项目的问题...`, index `thread_name` is `梳理问题原因`, visible row shows `梳理问题原因`.
- Base: older Codex install has no index file; visible row shows transcript `thread_name_updated`, then first user message, then fallback.
- Bad: parser stores first user message as the visible title and ignores `session_index.jsonl`, causing Codex Stats to disagree with Codex.

### 6. Tests Required

- Scanner test: duplicate index rows for the same id choose the last non-empty `thread_name`.
- Provider/store test: `titleOverride` wins over first-user-message title after parse or cache restore.
- Regression check: token/cost totals are unchanged by title-only overrides.

### 7. Wrong vs Correct

#### Wrong

```swift
let title = threadName ?? firstUserTitle ?? fallbackTitle
```

#### Correct

```swift
let displayStats = parsedStats.applyingTitleOverride(session.titleOverride)
```
