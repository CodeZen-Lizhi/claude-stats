# Claude Stats — Development Guide

## Build & Run

```bash
bash scripts/run-debug.sh
```

Generates `ClaudeStats.xcodeproj` from `project.yml`, builds Debug to
`/tmp/claude-stats-build`, refreshes Launch Services, and launches the app.

**IMPORTANT:** This is a menu-bar (`LSUIElement`) app. Do NOT `open -a "Claude Stats"`
or build to the default DerivedData path — multiple registered `.app` bundles with
the same bundle id cause Launch Services conflicts and the menu-bar item silently
fails to appear. Always use `/tmp/claude-stats-build` as the `-derivedDataPath` and
launch by full path (the script does this).

## Tests

```bash
bash scripts/run-tests.sh
```

## Regenerate the Xcode project

`ClaudeStats.xcodeproj` is generated, not committed. After editing `project.yml`
(or adding/removing source folders), run `bash scripts/generate.sh`.

## Provider code organization

Today there is one provider (Claude). Provider-specific behaviour lives under
`ClaudeStats/Providers/<Provider>/`; cross-provider logic lives in shared files
(`Models/`, `Services/`, `Utilities/`).

**Rule of thumb — per-provider data, shared behaviour:** any alias table, file
format quirk, or path convention that only one provider cares about belongs in
that provider's folder, behind the `Provider` protocol. How the canonical data
is rendered (formatters, the menu-bar label, the usage charts) is shared. When
you catch yourself writing `switch providerName { case "…": … }` in shared
code, stop — route it through a provider-owned method instead.

Adding a second provider should be: a new folder under `Providers/`, a type
conforming to `Provider`, and one line in `ProviderRegistry.all`. No changes to
shared code.

## Conventions

- Swift 6 language mode, `SWIFT_STRICT_CONCURRENCY = complete`. Keep it warning-free.
- Data models are `Sendable` value types. Stores and view models are
  `@MainActor @Observable`. File I/O (scanning, parsing) runs off the main actor
  as plain `async` functions on non-isolated types.
- Logging goes through `Log` (`os.Logger`), not `print`.
