<h1 align="center">Codex Statistics</h1>

<p align="center">
  A native macOS menu-bar dashboard for OpenAI Codex usage, sessions, cost, git activity, and local system health.
</p>

<p align="center">
  <a href="#what-it-does">What It Does</a> ·
  <a href="#install">Install</a> ·
  <a href="#privacy-and-data">Privacy</a> ·
  <a href="#build-from-source">Build</a>
</p>

Codex Statistics is a local-first macOS app for people who use OpenAI Codex heavily and want a clear picture of their work: how many sessions ran, which models were used, how many requests and tokens were spent, what the estimated cost looks like, which repositories were active, and whether Codex or the local machine may be the reason the day feels slow.

The app runs as a menu-bar utility, with an optional floating edge tab and a full main window for deeper analysis. It is Codex-only in the product UI; the source tree still keeps a provider boundary internally so Codex-specific parsing and shared analytics stay separated.

## What It Does

### Fast Status From The Menu Bar

- Show today, 7-day, 30-day, or all-time tokens or estimated cost directly in the macOS menu bar.
- Open a compact panel with Sessions, Usage, and Git panes.
- Refresh local stats manually or on an automatic cadence.
- Export a shareable PNG summary from the menu panel.
- Use the floating edge tab when the menu bar is crowded or hidden.

### Codex Usage Analytics

- Scan local Codex session data from `~/.codex/sessions`.
- Track sessions, requests, input/output/cache tokens, active days, streaks, peak hours, and favorite models.
- Show usage by model, token composition, cache behavior, and estimated cost.
- Keep a persisted usage ledger so deleted or moved sessions do not immediately erase historical totals.
- Compare standard API-style estimates with detailed transcript billing data when the transcript exposes enough detail.
- Display usage limits and recent usage trends in the main Usage view.

### Sessions And Transcripts

- Browse all discovered Codex sessions by project, model, token count, cost, and last activity.
- Open a session detail view with metadata, model breakdown, request stats, and transcript rendering.
- Search within transcripts and render large sessions in a bounded window so the UI stays responsive.
- Delete sessions from the app while preserving ledger history for aggregate accounting.

### Dashboard

- See an overview of historical sessions, requests, tokens, active days, streaks, peak activity, and top models.
- Switch between Overview and Models views.
- Inspect AI activity heatmaps across recent months.
- Monitor selected OpenAI Status product groups, including optional notifications.
- Optionally compare local AI activity with GitHub contribution activity when a GitHub token is configured.

### Git And Repository Activity

- Build a repository list from Codex sessions and optional workspace sources such as Cursor, Windsurf, Trae, Qoder, and JetBrains recent projects.
- Show commits, touched files, insertions, deletions, and AI usage correlation for the selected time window.
- Filter to commits authored by the local `git user.email`.
- Open a repository graph with branch lanes, refs, working tree status, commit details, and per-file churn.
- Inspect repository language and source-line statistics from `HEAD` or the working tree.

### System Monitor

- Enable a native system monitor view from Settings.
- Track CPU, memory, disk, network, power, GPU, and thermal pressure.
- Choose visible modules and refresh cadence: manual, 1s, 3s, 10s, or 30s.
- Use it as a quick sanity check when Codex activity, local builds, or network usage looks unusual.

### Settings And Maintenance

- Configure language, appearance, refresh cadence, launch behavior, menu-bar metric, token counting, and cost mode.
- Edit model pricing used by cost estimates.
- Choose repository sources for Git activity.
- Connect GitHub with a token stored in Keychain.
- Check for updates through Sparkle.
- Export diagnostics when debugging local data or app behavior.

## Install

Download the latest packaged build from [GitHub Releases](https://github.com/CodeZen-Lizhi/claude-stats/releases).

Codex Statistics uses Sparkle for in-app updates. The update feed is published at:

```text
https://codezen-lizhi.github.io/claude-stats/appcast.xml
```

Release packaging supports both signed/notarized builds and unsigned fallback builds. If macOS blocks an unsigned build on first launch, open it from Finder with right-click, then choose **Open**.

### Compatibility

- Apple Silicon Mac.
- Packaged releases target macOS 15 or later.
- The source project uses a macOS 14.0 deployment target and Swift 6 strict concurrency.
- Current release builds are `arm64`.

## Privacy And Data

Codex Statistics is designed to work from local files first.

- Codex sessions are read from `~/.codex/sessions`.
- Codex configuration is read from the local `~/.codex` area when needed for display or diagnostics.
- Git activity is collected by running local `git` commands against repositories discovered from configured workspace sources.
- GitHub features are off until enabled. The GitHub token is stored in Keychain.
- OpenAI Status and Sparkle update checks use network requests for their specific feature areas.
- Aggregate usage history is stored locally so totals remain useful even when a transcript is deleted or moved.

The app does not need a server to compute core session, token, cost, or repository statistics.

## Build From Source

Clone the repository:

```bash
git clone --recursive https://github.com/CodeZen-Lizhi/claude-stats.git
cd claude-stats
```

Install XcodeGen:

```bash
brew install xcodegen
```

Generate the Xcode project when you want to inspect or open it:

```bash
bash scripts/generate.sh
open ClaudeStats.xcodeproj
```

For normal local development, use the helper scripts:

```bash
bash scripts/run-debug.sh
bash scripts/run-tests.sh
```

`ClaudeStats.xcodeproj` is generated from [`project.yml`](project.yml). The debug launcher builds into `/tmp/Codex-stats-build` and launches the app by full path. That avoids Launch Services conflicts that can happen with menu-bar `LSUIElement` apps when multiple bundles share the same bundle identifier.

## Requirements For Development

- macOS with full Xcode installed and selected through `xcode-select`.
- Xcode 26 or newer.
- XcodeGen.
- Swift 6.

## Project Layout

```text
ClaudeStats/
  App/          App entry point, Info.plist, entitlements, lifecycle setup
  Features/     Feature-specific integrations
  Models/       Sendable value types and generated release history
  Providers/    Codex provider, scanner, parser, and provider protocol
  Resources/    Pricing data, app resources, bundled tool placeholders
  Services/     Stores, scanners, git, GitHub, status, diagnostics, updates
  ViewModels/   Observable state for screens and feature panels
  Views/        Menu bar, floating stats, main window, settings, Git, system UI
  Utilities/    Formatting, logging, localization, and shared helpers

ClaudeStatsTests/ Unit and integration tests
docs/             Product notes, screenshots, and documentation assets
scripts/          Project generation, tests, release, and appcast tooling
```

## Releases

The app version is managed in [`project.yml`](project.yml). Tagged releases are built by GitHub Actions, packaged, published to GitHub Releases, and used to update the Sparkle appcast.

Local release dry run:

```bash
bash scripts/release-build.sh 1.2.0
```

Version-only bump:

```bash
bash scripts/bump-version.sh 1.2.0
```

## Contributing

Issues and pull requests are welcome. Before opening a PR, run:

```bash
bash scripts/run-tests.sh
```

For app behavior changes, also run:

```bash
bash scripts/run-debug.sh
```

Keep Swift 6 strict concurrency warning-free and keep feature descriptions aligned with the Codex-only product surface.

## License

Codex Statistics is released under the [GNU Affero General Public License v3.0](LICENSE). Dependencies are declared in [`project.yml`](project.yml), including Sparkle for automatic updates.
