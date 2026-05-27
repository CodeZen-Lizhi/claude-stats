# App Code Specs

## Pre-Development Checklist

- Read [`codex-session-index.md`](codex-session-index.md) before changing Codex session discovery, display titles, visible session counts, or transcript-index reconciliation.
- Read [`session-deletion.md`](session-deletion.md) before changing session deletion, usage ledger retention, or Git attribution from session history.

## Quality Check

- Confirm Codex display titles prefer `session_index.jsonl` thread names over transcript-derived first-user-message fallbacks.
- Confirm transcript deletion does not delete or filter `UsageLedgerEvent` history.
- Confirm Git consumers that need historical attribution use live sessions plus deleted-session metadata, not only visible sessions.
