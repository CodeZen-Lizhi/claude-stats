# claude-statistics README comparison notes

## Source

* `https://raw.githubusercontent.com/sj719045032/claude-statistics/main/docs/README_zh.md`, fetched 2026-05-27.
* GitHub preview page and raw content appeared to differ; raw `main` content was used.

## What claude-statistics highlights

* Notch Island: live session cards in the MacBook notch/top capsule, waiting-input state, permission approval cards, provider-level notification toggles, global hotkey, keyboard navigation, no focus stealing.
* Plugin marketplace: discover/install/update/disable/uninstall `.csplugin`, SHA-256 verification, manifest trust, hot loading, categories for provider/terminal/share-card/subscription/utility.
* Precise terminal tab focus: Ghostty surface id to window/tab fallback, tty matching for iTerm2/Terminal, native CLI focus for Kitty/WezTerm/Alacritty.
* Multi-provider usage bar: provider cells in menu bar, icon plus rotating quota/time-window label, warning colors at 50% and 80%.
* Subscription monitoring: Claude 5h/7d, Codex JWT identity and local usage, Gemini grouped quotas, marketplace subscription endpoints, extra usage, retry/dashboard links, configurable refresh.
* Session management: recent sessions, project grouping, model/type coloring, batch delete, hover actions, resume/new session/copy identifiers.
* Transcript search: full transcript view, search across conversation and tool call content, previous/next match navigation, highlighted markdown/code/tool output.
* Share cards: roles, badges, proof metrics, QR code, native PNG export.
* Settings: preferred terminal, tab ordering, font scaling, plugin trust/reset, status-line integrations, diagnostic log export.
* Release tooling: Sparkle deltas, marketplace plugin package generation.

## What this project already covers

* Menu-bar panel with Sessions/Usage/Git and share/export footer.
* Codex-only provider boundary with `CodexProvider`, `SessionStore`, `UsageLimitStore`, OpenAI status, and Codex usage-limit bridge.
* Session list grouping/search/sort by project, title/path, recent/tokens/cost.
* Session detail with stat cards, model breakdown, basic transcript messages, reveal transcript and open project folder.
* Usage overview with total tokens/cost/sessions/requests, period tabs, trend chart, cache hit/cached tokens, model breakdown.
* PNG export window with pane/time range/chart/appearance controls.
* Model pricing settings with local JSON editing and pricing refresh attempt.
* Git, GitHub, System Monitor, feature toggles, Sparkle updates, and floating edge tab.

## Gaps that fit current product direction

### High-value, aligned

1. Transcript search and richer transcript rendering.
   * Current session detail renders plain text messages and role/model/timestamp. It does not expose full search navigation, markdown/code rendering, tool-call detail panes, or highlighted results.
   * Strong fit because it deepens the existing Codex transcript detail page without changing provider scope.

2. Session action polish.
   * Current rows expose context-menu reveal/open-folder only. README_zh describes hover actions for resume/new session/copy/delete and batch delete.
   * Strong fit if scoped to Codex CLI session/project actions and guarded by confirmations.

3. Menu-bar usage warning states.
   * Current menu-bar settings choose tokens/cost and period. README_zh adds quota/time-window rotation and warning colors.
   * For this project, borrow only Codex usage-limit warning semantics, not multi-provider cells.

4. Share card enrichment.
   * Current export is a polished panel snapshot. README_zh's roles, badges, proof metrics, and QR code would make sharing more memorable.
   * Fit is good as an optional mode layered over existing `ShareExportView`.

5. Diagnostic log export.
   * README_zh lists app log export; this project already has debugging/status surfaces but no obvious user-facing diagnostic export in settings.
   * Good supportability win with limited product risk.

### Medium-value, needs slicing

6. Real-time activity island / floating live activity.
   * Deferred by user decision. Do not change Floating Edge Tab for now.
   * Keep only the lightweight navigation idea: when a session/activity item exists elsewhere in the app, clicking it may open the corresponding session detail or project view.

7. Precise terminal tab return.
   * Excluded by user decision. Do not borrow Ghostty surface id/window/tab mapping, tty matching, or terminal tab-level focus.
   * Keep only lower-risk session actions such as reveal transcript, open project folder, copy session info, and optionally open a project in the user's normal terminal if that becomes useful.

8. Status-line integration management.
   * This project already has Codex usage-limit bridge concepts. Borrowing visible install/update/diagnose controls may reduce setup confusion.
   * Needs inspection of current bridge UI before implementation.

9. Rich usage hover tooling.
   * README_zh mentions chart interpolation tooltip and crosshair hover. This project has Charts-based trend rendering; tooltip/crosshair could improve insight density.
   * Best handled as a focused Usage chart UX improvement.

### Low-fit or defer

10. General plugin marketplace.
    * Powerful but conflicts with current Codex-only product simplification and increases trust/update/security surface.
    * Consider only after a concrete extension point is needed, such as share-card templates or subscription endpoints.

11. Reintroducing Claude/Gemini providers and multi-provider switcher.
    * Explicitly conflicts with current product PRD unless product direction changes.

12. Marketplace subscription endpoints.
    * Useful for broader tool aggregation but likely premature for Codex-only.

13. Sparkle delta workflow parity.
    * Current release workflow already publishes Sparkle appcast; delta support might reduce bandwidth but is not a user-facing feature priority.

## Suggested MVP candidates

1. Transcript search MVP.
   * Add search field to session detail, result count, next/previous navigation, highlighted plain text matches, and tool/system role filters if already parsed.

2. Codex session actions MVP.
   * Add row hover buttons or detail actions for copy session id/path, open project in preferred terminal, delete with confirmation, and rescan.

3. Usage-limit warning MVP.
   * Add threshold-colored menu-bar/panel indicator for Codex usage windows, with preferences for which signal appears in the menu bar.

4. Share card v2 MVP.
   * Add a second export template with role/badge/proof-metric sections using existing parsed stats, no QR code initially unless a stable target URL exists.

5. Diagnostic bundle MVP.
   * Add Settings/About action to export app logs, environment snapshot, selected preferences, scanner status, and recent parse errors with sensitive paths/tokens redacted where needed.

## Diagnostic export details to borrow

`claude-statistics` only names diagnostic log export in the README, but it sits beside plugin/status-line/provider/usage tooling, so the useful pattern to borrow is a user-facing support bundle rather than a raw log dump.

Borrow:

* Settings entry for "Export diagnostics" so non-technical users can produce a support artifact.
* Recent app/runtime logs focused on startup, scanner, parser, usage limit, status, update, and integration failures.
* Integration status summary for Codex CLI, status-line/usage-limit bridge, Git tooling, GitHub, OpenAI status, Sparkle, and local data directories.
* Scanner/parser report with counts, timestamps, failure categories, and file metadata summaries.
* Human-readable diagnosis summary that points to likely causes such as missing permissions, unreadable session directory, stale usage-limit cache, parse failures, or network status errors.

Do not borrow by default:

* Full transcript content.
* Prompt/message text.
* Tokens, JWT/OAuth values, API keys, access tokens, Git diffs, or private code.
* Full absolute paths unless redacted or explicitly confirmed by the user.
