# Claude Statistics Inspiration Notes

This note captures the strongest product ideas from Claude Statistics that are worth reusing as reference points in Claude Stats.

## What To Borrow

### Share Cards

- Turn usage data into something people want to share.
- Keep the output visual, polished, and metric-driven.
- Use achievements, roles, and proof metrics to make the card feel earned instead of decorative.

### Model Pricing Management

- Let the user inspect and edit model pricing in one place.
- Make pricing visible in the workflow, not buried in a settings footnote.
- Treat pricing as product logic, not just a static config file.

### Statistics And Cost Analysis

The strongest pattern here is a complete local transcript-based analytics pipeline.

- Full summary: total cost, session count, token count, message count.
- Period aggregation: by day, week, month, and year.
- Interactive cost chart: click into a period to drill down.
- Period detail: overview, trend chart, token breakdown, model breakdown.
- Cache token detail: 5-minute write, 1-hour write, cache read.
- Period list: optimized for scanning expensive or token-heavy ranges.
- Stable all-time summary: computed from parsed sessions directly, so it does not change when the selected period changes.

### Session List

- Search by project path, topic, session name, or session ID.
- Show recent sessions for quick return.
- Group by project directory with expand/collapse.
- Expose the most useful facts at a glance: title, model, message count, token count, cost, context usage, and time.
- Support batch selection and bulk delete.
- Auto-refresh from file watching or provider-specific rescans.
- Offer hover actions for common workflows.

### Session Detail

- Show one-session overview clearly: model, duration, file size, start/end time.
- Break out token usage precisely: input, output, cache write, cache read.
- Show multi-model cost and token usage.
- Surface context window utilization visually.
- Include token distribution and cache detail.
- Rank tool usage and show session trends.

## Why These Matter

- They convert raw local data into decisions the user can act on.
- They make the app feel like a workflow tool, not a passive report viewer.
- They create a reusable product language for stats, cost, and session analysis.
- They are strong candidates for future Claude Stats features when the same UX pattern fits the existing architecture.

## Notes For Future Work

- Prefer local-first computation when possible.
- Keep all-time totals stable across period filters.
- Make drill-down paths obvious.
- Preserve scan speed and searchability as data grows.
- Reuse these patterns only where they fit the Claude Stats domain and existing navigation model.
