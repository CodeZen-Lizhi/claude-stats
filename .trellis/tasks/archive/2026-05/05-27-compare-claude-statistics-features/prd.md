# brainstorm: compare claude-statistics features

## Goal

Compare `sj719045032/claude-statistics`'s Chinese README against this Codex-only `claude-stats` project, identify feature details worth borrowing, and converge on a prioritized product backlog that fits this app's local-first macOS menu-bar direction without reintroducing unsupported scope by accident.

## What I already know

* User asked for a careful comparison between `docs/README_zh.md` in `sj719045032/claude-statistics` and this project.
* This project is a native macOS menu-bar app focused on Codex session stats, usage, costs, local repository activity, status, and debugging context.
* This project intentionally keeps the AI session provider surface Codex-only, even though shared provider abstractions remain internally.
* Current project already has: menu-bar Usage/Sessions/Git panes, grouped/searchable sessions, basic session transcript display, usage charts, cache statistics, share PNG export, model pricing editor, OpenAI status, Git/GitHub comparison, System Monitor, Sparkle updates, and a floating edge tab.
* `claude-statistics` README emphasizes a broader product: Claude Code + Codex CLI + Gemini CLI + plugin marketplace, Notch Island, precise terminal tab focus, subscription quota monitoring, transcript search, rich session operations, and highly gamified share cards.

## Assumptions (temporary)

* Borrowing should favor Codex-specific value and avoid re-adding multi-provider UI unless the product direction changes.
* Features that improve local workflow, diagnostics, transcript inspection, sharing, and menu-bar visibility are more aligned than cloud/community/plugin marketplace expansion.

## Requirements (evolving)

* Produce a fact-backed comparison of current capabilities versus `claude-statistics`.
* Separate immediately borrowable feature details from ideas that conflict with Codex-only scope.
* Prioritize borrow candidates by user value, implementation risk, and fit with current architecture.
* Identify MVP slices that could be implemented later as small PRs.
* For diagnostic log export, borrow the supportability workflow from `claude-statistics`: user-facing export entry, app/runtime log bundle, integration status summary, and a readable diagnosis report, while keeping transcript/code/token data excluded by default.
* Exclude precise terminal tab return from the borrow list; do not pursue Ghostty/iTerm/Terminal tab-level focus.
* Do not change Floating Edge Tab for now; keep live activity/floating UI ideas as future consideration only.
* Keep a low-risk navigation borrow: clicking a session/activity item may open the corresponding session detail or project in the app.

## Borrow List (converged)

### P0 - Most Worth Borrowing

* Transcript viewer upgrade: search within transcript, previous/next match navigation, highlighted matches, Markdown/code rendering, and clearer tool-call display.
* Session workflow actions: recent sessions plus row/detail actions for reveal transcript and open project.
* Diagnostic export: user-facing export bundle for app logs, scanner/parser report, integration status, permissions, and human-readable likely-cause summary, with sensitive content excluded by default.

### P1 - Useful Polish / Second Wave

* Share card v2: add a more social export template with role, achievement badges, and proof metrics.
* Usage chart interaction: richer hover tooltip, crosshair/readout, and clearer trend inspection for token/cost charts.

### Deferred / Future Consideration

* Floating Edge Tab live activity: keep for later; do not change the existing Floating Edge Tab in this scope.
* Plugin-like extension points: consider only small, bounded extension points such as share-card templates after core workflows are solid.

### Explicitly Not Borrowing

* Multi-provider provider switcher, Claude/Gemini providers, and multi-provider usage bar.
* General plugin marketplace with hot loading, trust management, and third-party provider/subscription plugins.
* Precise terminal tab return, including Ghostty surface id mapping, tty matching, and terminal tab activation.
* Full Notch Island behavior, permission approval cards, or focus-stealing-sensitive floating activity UI.
* Exporting full transcripts, prompts, tokens, JWT/OAuth/API keys, Git diffs, or private code in diagnostics.
* Codex 5h/weekly usage-limit alerting and status-line / usage-limit bridge management.

## Acceptance Criteria

* [x] External README was fetched from `main` raw GitHub content.
* [x] Current project README, product PRD, inspiration notes, and relevant Swift UI files were inspected.
* [x] Borrowable items are grouped by priority and rationale.
* [x] Diagnostic export borrow scope is narrowed to supportability details rather than sensitive user content.
* [x] Final implemented scope is limited to transcript viewer upgrade, recent-session navigation/actions, diagnostics export, share card v2, and Usage chart hover readout.
* [x] Codex usage-limit alerting, status-line/bridge management, Floating Edge Tab redesign, precise terminal tab return, multi-provider support, and plugin marketplace are excluded.

## Definition of Done (team quality bar)

* Tests added/updated if implementation follows.
* Lint / typecheck / CI green if implementation follows.
* Docs/notes updated if behavior changes.
* Rollout/rollback considered if risky.

## Out of Scope (explicit)

* Reintroducing Claude/Gemini session providers or a multi-provider switcher without an explicit product decision.
* Building a general plugin marketplace before a smaller extension point is proven useful.
* Precise terminal tab return, including Ghostty surface id/window/tab mapping or tty-based tab matching.
* Floating Edge Tab redesign or real-time activity island behavior in the MVP.
* Codex 5h/weekly usage-limit alerting and status-line / usage-limit bridge management.

## Research References

* [`research/claude-statistics-readme.md`](research/claude-statistics-readme.md) - README-driven feature comparison and borrow candidates.

## Technical Notes

* External source: https://raw.githubusercontent.com/sj719045032/claude-statistics/main/docs/README_zh.md
* Project docs inspected: `README.md`, `docs/claude-stats-product-prd.md`, `docs/claude-statistics-inspiration-notes.md`.
* Project code inspected: `SessionListView`, `SessionRow`, `SessionDetailView`, `UsageView`, `ShareExportView`, `MenuPanelView`, `MenuBarSettingsView`, `SettingsSection`, `FeaturesSettingsView`.
* Direct `curl` to GitHub raw was reset; retried with local proxy per project instruction and succeeded.
