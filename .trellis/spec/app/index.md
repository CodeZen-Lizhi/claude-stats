# App Code Specs

## Pre-Development Checklist

- Read [`codex-session-index.md`](codex-session-index.md) before changing Codex session discovery, display titles, visible session counts, or transcript-index reconciliation.
- Read [`codex-transcript-usage.md`](codex-transcript-usage.md) before changing Codex transcript token parsing, usage ledger events, parser revisions, or request/token aggregation.
- Read [`session-deletion.md`](session-deletion.md) before changing session deletion, usage ledger retention, or Git attribution from session history.

## Quality Check

- Confirm Codex display titles prefer `session_index.jsonl` thread names over transcript-derived first-user-message fallbacks.
- Confirm forked Codex transcripts do not count replayed parent-history `token_count` records as new usage.
- Confirm transcript deletion does not delete or filter `UsageLedgerEvent` history.
- Confirm Git consumers that need historical attribution use live sessions plus deleted-session metadata, not only visible sessions.
