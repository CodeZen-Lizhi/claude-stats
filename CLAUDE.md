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

## Releasing

The version number lives in `project.yml` (`MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`).
`Info.plist` references those via `$(…)`, and `SettingsView`'s About row reads them back from
`Bundle.main` at runtime — so a release just needs the version baked into the build.

To cut a release, push a semver tag:

```bash
git tag v1.2.0 && git push origin v1.2.0
```

`.github/workflows/release.yml` (runs on `macos-26` with Xcode 26.4.1) then: writes `1.2.0` into `project.yml`
(build number = the workflow run number), builds a Release `Claude Stats.app`, packages it,
publishes a GitHub Release **on the public companion repo `1pitaph/claude-stats-releases`** with
the artifact(s) attached, and commits the bumped `project.yml` back to `master` here.

The source lives in a **private** repo; binaries and the Sparkle appcast live in the **public**
`claude-stats-releases` repo so anyone can download a release / receive an update. The release
workflow uses a fine-grained PAT (`RELEASES_REPO_TOKEN`, repo secret, Contents: Read and write
on `claude-stats-releases`) to push across repos.

Packaging has two modes, picked automatically:

- **Signed + notarized DMG** — when all six signing secrets are set on the repo
  (`BUILD_CERTIFICATE_BASE64`, `P12_PASSWORD`, `KEYCHAIN_PASSWORD`, `APPLE_TEAM_ID`,
  `NOTARY_APPLE_ID`, `NOTARY_PASSWORD`; see the comment block at the top of the workflow).
- **Un-notarized DMG + .zip** — when those secrets are absent (the default). Gatekeeper warns
  on first launch; users open it via right-click ▸ Open.

`scripts/release-build.sh` mirrors this: with `SIGN_IDENTITY` (plus `APPLE_TEAM_ID`, `APPLE_ID`,
`APP_PASSWORD`) it codesigns with hardened runtime, notarizes via `notarytool`, and staples;
without it, it produces an ad-hoc DMG + zip. Dry-run locally: `bash scripts/release-build.sh 1.2.0`.
Bump the version without building: `bash scripts/bump-version.sh 1.2.0`.

## Auto-update (Sparkle)

The app embeds [Sparkle 2](https://sparkle-project.org) (SPM dep in `project.yml`).
`UpdaterController` wraps `SPUStandardUpdaterController`; it's owned by
`AppEnvironment` and started from `AppEnvironment.start()`. Because this is an
`LSUIElement` app, `UpdaterController` flips the activation policy to `.regular`
while Sparkle's windows are up and back to `.accessory` when the session ends.
Settings ▸ About has a "Check for Updates…" button; scheduled background checks
are on by default (`SUEnableAutomaticChecks` in `Info.plist`).

The update feed is `appcast.xml` on the `gh-pages` branch of the public releases
repo, served at `https://1pitaph.github.io/claude-stats-releases/appcast.xml`
(`SUFeedURL` in `Info.plist`). On each tagged release the workflow EdDSA-signs the
archive (`scripts/publish-appcast.sh` → `scripts/update-appcast.py`) and pushes an
updated `appcast.xml` to that branch via `RELEASES_REPO_TOKEN`. This works the same
whether the release is the un-notarized zip/DMG or the signed+notarized DMG —
Sparkle just downloads whichever asset the appcast points at (it prefers the `.zip`
when present). Release notes are generated from the source repo's commit log
between this tag and the previous semver tag, written as both markdown (used as
the GitHub Release body) and minimal HTML (embedded directly in the appcast's
`<description>` CDATA so Sparkle renders them inline without a webview fetch).

**One-time setup:**

1. Create the public releases repo `1pitaph/claude-stats-releases` (any commit on
   the default branch; `softprops/action-gh-release` needs one to anchor the tag).
2. Create a fine-grained PAT scoped to `claude-stats-releases` with
   **Contents: Read and write**. Add it to this (private) repo's Actions secrets
   as `RELEASES_REPO_TOKEN`.
3. Sparkle keys: `./bin/generate_keys` to generate (private key into login
   keychain, public key printed), then `./bin/generate_keys -x sparkle_private_key`
   to export the private key for CI. Put the public key in `Info.plist` as
   `SUPublicEDKey`; add the exported file's contents as repo secret
   `SPARKLE_PRIVATE_ED_KEY` (then `rm` the file — keychain keeps a copy).
4. After the first release runs, enable GitHub Pages on the public repo:
   Settings → Pages → Source = `gh-pages` branch / `/ (root)`.

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
