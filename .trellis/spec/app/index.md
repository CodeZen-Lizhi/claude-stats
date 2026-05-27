# App Code Specs

## Pre-Development Checklist

- Read [`session-deletion.md`](session-deletion.md) before changing session deletion, usage ledger retention, or Git attribution from session history.

## Quality Check

- Confirm transcript deletion does not delete or filter `UsageLedgerEvent` history.
- Confirm Git consumers that need historical attribution use live sessions plus deleted-session metadata, not only visible sessions.
