# Claude Stats

A native macOS menu-bar app that monitors your [Claude Code](https://docs.anthropic.com/en/docs/claude-code) usage — sessions, tokens, and estimated cost — read directly from `~/.claude/projects/`.

It is a slimmed-down, single-provider take on the open-source [Claude Statistics](https://github.com/sj719045032/claude-statistics) app. The provider layer is shaped so additional AI CLIs (Codex, Gemini, …) can be added later without restructuring.

## Build

The Xcode project is generated from [`project.yml`](project.yml) with [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```bash
brew install xcodegen        # one-time
bash scripts/generate.sh     # writes ClaudeStats.xcodeproj (gitignored)
open ClaudeStats.xcodeproj
```

Or use the helper scripts:

```bash
bash scripts/run-debug.sh    # generate + build Debug + launch the menu-bar app
bash scripts/run-tests.sh    # generate + run the unit tests
```

## Layout

```
ClaudeStats/
  App/         @main entry point, app environment, Info.plist, entitlements
  Models/      Sendable value types (Session, TokenUsage, ModelUsage, …)
  Providers/   Provider protocol + registry; Providers/Claude/* reads ~/.claude
  Pricing/     per-million-token rates + bundled default-pricing.json
  Services/    SessionStore — the @MainActor @Observable source of truth
  ViewModels/  per-screen view models
  Views/       MenuBarExtra label + the dropdown panel (Sessions / Usage / Settings)
  Utilities/   formatters, logging
ClaudeStatsTests/   parser / pricing / scanner tests + fixtures
scripts/            generate.sh, run-debug.sh, run-tests.sh
```

## Requirements

- macOS 14+
- Xcode 26+ (Swift 6 language mode, strict concurrency `complete`)
