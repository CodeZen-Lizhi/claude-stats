# brainstorm: fix usage stats and pricing accuracy

## Goal

Clarify how the app currently computes Codex usage, tokens, cache tokens, and cost, then decide the minimal fix so the app matches the user-provided real billing/usage data.

## What I already know

* User reports current usage statistics are inaccurate.
* Screenshot shows real data for today: API key codex, 1328 requests, 110M tokens, $104.70 total cost.
* Provider rows include Alpha, okinto, AI INPUT, gether with request counts, input/output/cache token breakdowns, costs, cache hit rates, success rates, and average response times.
* Current app does not read OpenAI billing/usage dashboard data. It scans local Codex transcript files under `~/.codex/sessions/**/rollout-*.jsonl`.
* Current app-like local aggregate for 2026-05-26 Asia/Shanghai is 121 sessions, 1388 `token_count` events, 119,554,686 tokens including cache-read, and $112.93 estimated cost.
* No user override file currently exists at `~/.claude-stats/pricing.json`; bundled pricing is being used.

## Assumptions (temporary)

* The app has hardcoded or provider-owned model pricing tables that may be stale or incomplete.
* The mismatch may come from either token aggregation, cache-token accounting, model-to-price mapping, or time window/provider grouping.

## Open Questions

* Which source of truth should the app use for pricing going forward: checked-in static table, user-configurable table, or imported billing data?

## Requirements (evolving)

* Identify current usage aggregation path.
* Identify current model pricing configuration path.
* Compare code behavior against the user-provided real data shape.
* Treat OpenAI dashboard/API numbers as the factual target if the user confirms dashboard parity is the goal.

## Acceptance Criteria (evolving)

* [ ] Can explain exactly how current usage totals are computed.
* [ ] Can point to where every model price is configured.
* [ ] Can propose a minimal correction path for matching real data.

## Definition of Done (team quality bar)

* Tests added/updated where behavior changes.
* Lint / typecheck / CI green.
* Docs/notes updated if behavior changes.
* Rollout/rollback considered if risky.

## Out of Scope (explicit)

* No code changes before confirming the intended source of truth for pricing if multiple valid approaches exist.

## Technical Notes

* Pricing table lives in `ClaudeStats/Pricing/default-pricing.json`; users can override with `~/.claude-stats/pricing.json`.
* `ModelPricing` computes USD cost as per-million-token rates for input, output, cache read, and cache write categories.
* `CodexTranscriptParser` reads `last_token_usage` from `token_count` events, attributes each delta to the most recent `turn_context.model`, and splits `cached_input_tokens` out of `input_tokens`.
* `UsageSummary` filters sessions into a period by session last activity, then aggregates each parsed session's model totals. Codex sessions do not currently populate `billableMessages`, so cross-file dedupe is not available on that path.
