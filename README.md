<p align="center">
  <img src="docs/assets/claude-stats-icon.png" alt="Claude Stats app icon" width="128" height="128">
</p>

<h1 align="center">Claude Stats</h1>

<p align="center">
  Native macOS menu-bar stats and Notch Island for AI coding work.
</p>

<p align="center">
  <a href="#features">Features</a> ·
  <a href="#screens">Screens</a> ·
  <a href="#install">Install</a> ·
  <a href="#build-from-source">Build From Source</a> ·
  <a href="#open-source--third-party-modules">Open Source</a> ·
  <a href="#contributing">Contributing</a>
</p>

Claude Stats is an open-source native macOS app for people who work in AI coding tools all day. It runs from the menu bar, reads local usage and activity data, and turns it into quick answers about sessions, tokens, cost, limits, repository activity, local status, and debugging context.

The app began as a focused macOS take on the open-source [Claude Statistics](https://github.com/sj719045032/claude-statistics) project. It is now a Codex-only product with a provider abstraction kept internally for clean session, usage, and configuration boundaries, plus a Notch Island surface.

## Reference Notes

- [Claude Statistics inspiration notes](docs/claude-statistics-inspiration-notes.md) collects product ideas worth reusing here, especially share cards, model pricing management, and transcript-based stats and cost analysis.
- [Claude Stats product PRD](docs/claude-stats-product-prd.md) documents the current product by feature family for future refactors and second-development work.

## Features

- Menu-bar usage stats for AI coding sessions, tokens, estimated cost, and recent activity.
- Codex session log discovery, parsing, usage stats, estimated cost, usage limits, and OpenAI service status.
- API provider switcher for Codex CLI configuration.
- Git and repository activity views, including optional bundled Git tooling for release builds.
- An Atoll-backed Notch Island surface for optional media, timer, stats, clipboard, and related modules.
- Ops tools for Homebrew packages and developer environment checks.
- Sparkle-based automatic updates for packaged releases.

## Screens

Screenshots and GIF demos live in [`docs/assets/screens`](docs/assets/screens), grouped here by product area.

<details open>
<summary><strong>Menu-bar extra</strong></summary>

<table>
  <tr>
    <th align="left" width="33%">Usage panel</th>
    <th align="left" width="33%">Activity panel</th>
    <th align="left" width="33%">Git panel</th>
  </tr>
  <tr>
    <td valign="top" width="33%">
      <img src="docs/assets/screens/menubar-usage.gif" alt="Menu-bar extra usage panel" width="100%">
    </td>
    <td valign="top" width="33%">
      <img src="docs/assets/screens/menubar-activity.gif" alt="Menu-bar extra activity panel" width="100%">
    </td>
    <td valign="top" width="33%">
      <img src="docs/assets/screens/menubar-git.gif" alt="Menu-bar extra Git panel" width="100%">
    </td>
  </tr>
</table>

<details>
<summary><strong>Share stats export</strong></summary>

<img src="docs/assets/screens/menubar-share-stats.gif" alt="Menu-bar share stats export flow">

</details>

</details>

<details open>
<summary><strong>Stats and activity</strong></summary>

<p><strong>Dashboard overview</strong></p>
<img src="docs/assets/screens/dashboard-overview.png" alt="Claude Stats dashboard overview">

<p><strong>Sessions overview</strong></p>
<img src="docs/assets/screens/sessions-overview.png" alt="Codex session statistics overview">

<p><strong>Token usage and limits</strong></p>
<img src="docs/assets/screens/usage-token-limits.png" alt="Token usage and usage limits">

<p><strong>AI-assisted focus timeline</strong></p>
<img src="docs/assets/screens/activity-focus-timeline.png" alt="AI-assisted focus timeline">

</details>

<details>
<summary><strong>Configuration and local knowledge</strong></summary>

<p><strong>Plans and config browser</strong></p>
<img src="docs/assets/screens/configs-plans-browser.png" alt="Plans and config browser">

<p><strong>Skills library</strong></p>
<img src="docs/assets/screens/skills-library.png" alt="Local and plugin skills library">

</details>

<details>
<summary><strong>Developer tools</strong></summary>

<p><strong>API provider switcher</strong></p>
<img src="docs/assets/screens/provider-switcher.png" alt="API provider switcher">

<p><strong>Repository workspace</strong></p>
<img src="docs/assets/screens/git-repository-workspace.png" alt="Git repository workspace">

</details>

<details>
<summary><strong>Ops</strong></summary>

<p><strong>Homebrew packages</strong></p>
<img src="docs/assets/screens/ops-homebrew-packages.png" alt="Homebrew package inspector">

<p><strong>Developer environment check</strong></p>
<img src="docs/assets/screens/ops-environment-check.png" alt="Developer environment check">

</details>

<details>
<summary><strong>Settings</strong></summary>

<p><strong>Feature toggles</strong></p>
<img src="docs/assets/screens/settings-features.png" alt="Feature settings">

</details>

## Install

Packaged builds are published through the public release mirror:

- [GitHub Releases](https://github.com/1pitaph/claude-stats-releases/releases)
- [Sparkle appcast](https://1pitaph.github.io/claude-stats-releases/appcast.xml)

Release packaging supports both signed/notarized builds and unsigned fallback builds. If you use an unsigned build, macOS Gatekeeper may require opening it with right-click, then **Open**.

### Compatibility

Current packaged releases support Apple Silicon Macs running macOS 15 or later. The app bundle still carries a macOS 14 deployment target for the main app shell, but packaged releases include runtime components whose practical floor is macOS 15.

Intel Macs are not supported by current releases. The last public universal build with both `x86_64` and `arm64` slices was [v1.3.9](https://github.com/1pitaph/claude-stats-releases/releases/tag/v1.3.9); releases from v1.3.11 onward ship an `arm64` main executable.

## Privacy & Data

Claude Stats is local-first. Core usage stats are read from local Codex data such as `~/.codex/sessions/`; optional activity features may request macOS permissions such as Full Disk Access, Accessibility, or Screen Recording.

Network-facing features are feature-specific: Sparkle checks for updates, OpenAI status views may query public status pages, and GitHub-related views connect only when configured.

## Build From Source

Clone with submodules:

```bash
git clone --recursive https://github.com/1pitaph/claude-stats.git
cd claude-stats
```

Install local build tools:

```bash
brew install xcodegen
```

Generate the Xcode project if you want to inspect it directly:

```bash
bash scripts/generate.sh
open ClaudeStats.xcodeproj
```

For normal development, prefer the helper scripts:

```bash
bash scripts/run-debug.sh  # generate + build Debug + launch the menu-bar app
bash scripts/run-tests.sh  # generate + build test dependencies + run unit tests
```

`ClaudeStats.xcodeproj` is generated from [`project.yml`](project.yml) with [XcodeGen](https://github.com/yonaskolb/XcodeGen). The debug launcher builds into the canonical `/tmp/Codex-stats-build` DerivedData path and launches the app by full path; this avoids Launch Services conflicts with menu-bar (`LSUIElement`) builds that share the same bundle identifier.

## Requirements

- Apple Silicon Mac with macOS 15+
- Xcode 26+ with Swift 6 language mode
- XcodeGen for project generation

## Project Layout

```
ClaudeStats/
  App/          @main entry point, app environment, Info.plist, entitlements
  Features/     feature-specific app integrations such as Notch Island
  Models/       Sendable value types and generated release history
  Providers/    provider protocol, registry, and Codex scanner/parser
  Resources/    pricing data, Git tools placeholder, app resources
  Services/     stores, scanners, and system integrations
  ViewModels/   per-screen and feature view models
  Views/        menu bar, main window, settings, ops, and activity UI
  Utilities/    formatters, logging, shared helpers
AtollEmbed/       app-side wrapper for the Atoll/DynamicIsland integration
ThirdParty/       git submodules for Atoll and CppJieba
ClaudeStatsTests/ parser, scanner, settings, integration, and feature tests
docs/assets/      README images, icons, screenshots, and GIFs
scripts/          project generation, local run/test, release, appcast tooling
```

## Open Source & Third-Party Modules

Claude Stats is released under the [GNU Affero General Public License v3.0](LICENSE). The app also embeds and adapts several major open-source projects:

| Project | License | How Claude Stats uses it |
| --- | --- | --- |
| [Atoll / DynamicIsland](https://github.com/1pitaph/Atoll) | GPL-3.0 | Integrated through `AtollEmbed` for the optional Notch Island surface and modules. Its [`NOTICE`](ThirdParty/Atoll/NOTICE) and [`COPYRIGHT_ASSETS`](ThirdParty/Atoll/COPYRIGHT_ASSETS) files remain part of the attribution trail. |

Additional Swift Package Manager dependencies include Sparkle, Defaults, KeyboardShortcuts, SwiftUIIntrospect, Lottie, MacroVisionKit, SkyLightWindow, AtollExtensionKit, and Swift Collections. Those packages keep their upstream licenses and notices.

## Contributing

Issues and pull requests are welcome. Before opening a PR, run:

```bash
bash scripts/run-tests.sh
```

For app behavior changes, also run:

```bash
bash scripts/run-debug.sh
```

Keep Swift 6 strict concurrency warning-free. When changing Atoll integration code, make the source changes in the relevant submodule/fork first, then update the submodule pointer in this repo.
