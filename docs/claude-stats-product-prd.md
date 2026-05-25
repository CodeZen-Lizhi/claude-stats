# Claude Stats Product PRD

This document translates the current Claude Stats codebase into a product-level reference for future extension work.

## Goal

Claude Stats is a native macOS menu-bar app for people who spend all day in AI coding tools. The product turns local session data, usage data, status data, and developer tooling data into a compact workflow surface.

This PRD describes the existing product as it works today so future changes can preserve the same intent and module boundaries.

## Product Principles

- Local-first by default.
- Fast access from the menu bar and main window.
- Deep drill-down when the user needs detail.
- Shared behavior should stay in shared modules; provider-specific quirks belong to provider modules.
- UI should surface the current working context, not just raw metrics.

## Core Product Areas

### 1. Menu Bar Surface

The app must provide a lightweight menu-bar experience for quick access to the most important facts.

- Show usage, activity, and Git-related summaries.
- Provide direct navigation into the main window.
- Keep the interaction fast enough for repeated daily use.

### 2. Session Discovery And Analysis

The app must discover local sessions from supported providers and parse them into a common session model.

Supported or recognized providers:

- Claude Code
- OpenAI Codex
- Gemini
- Kimi
- MiniMax

Current behavior:

- Claude and Codex have concrete on-disk parsing pipelines.
- Gemini, Kimi, and MiniMax are recognized in the UI, but their session parsers are future work.
- Session updates should refresh automatically when local files change.

### 3. Session List

The session list is the primary browsing surface for local history.

Requirements:

- Search by project path, topic, session name, or session ID.
- Show recent sessions for quick return.
- Group sessions by project directory.
- Support expand/collapse for grouped results.
- Show the key facts at a glance: title, model, message count, token count, cost, context usage, and time.
- Support batch selection and bulk delete.
- Refresh automatically from file watching or provider-specific rescans.
- Offer hover shortcuts for common actions such as new session, resume, open transcript, delete, and copy path.

### 4. Session Detail

Each session detail view must explain one session clearly.

Requirements:

- Show model, duration, file size, start time, and end time.
- Show exact token accounting: input, output, cache write, and cache read.
- Show multi-model cost breakdown.
- Show context window utilization.
- Show token distribution and cache detail.
- Show tool usage ranking and a trend chart.

### 5. Statistics And Cost Analysis

This is the core analytical view for local transcript data.

Requirements:

- Full summary of total cost, session count, token count, and message count.
- Period aggregation by day, week, month, and year.
- Interactive cost bar chart with drill-down into period detail.
- Period detail pages containing overview, trend chart, token distribution, and model breakdown.
- Cache token detail for 5-minute write, 1-hour write, and cache read.
- Period list optimized for scanning expensive or token-heavy windows.
- All-time summary must be computed from parsed sessions directly so it does not change when the selected period changes.

### 6. Usage Limits And Service Status

The app must surface provider usage and provider health in a way the user can act on.

Requirements:

- Show usage-limit status where supported.
- Show service-status views for supported providers.
- Surface alerts and permission state clearly.
- Keep usage-limit data separate from long-term session stats.

### 7. Provider Configuration And Switching

The app includes an API Provider Switcher for managing provider configuration.

Requirements:

- Switch between providers from the configuration surface.
- Inspect and edit provider configuration entries.
- Support key storage mode selection.
- Keep provider-specific configuration handling in provider-specific code paths.

### 8. Sharing And Presentation

The app should support shareable output that makes analytics feel presentable.

Requirements:

- Generate share cards from usage or stats data.
- Make the output visual and metric-driven.
- Keep the exported result polished enough for sharing.

### 9. Developer Tooling Surfaces

The app must expose the auxiliary developer tools already present in the product.

Current surfaces:

- Git and repository activity
- Embedded terminal
- Network debugging
- LinuxDo integration
- Local AI model management
- Skills library
- System monitoring
- Ops tooling
- AI config browsing

### 10. Notch Island And Floating Stats

The product includes two fast surfaces for passive monitoring.

Requirements:

- Provide a Notch Island surface for live session context.
- Provide floating stats for quick status visibility.
- Keep these surfaces optional and driven by app preferences.

### 11. Settings

Settings should be the control plane for feature visibility and behavior.

Current settings families include:

- General
- Features
- Menu bar
- Notch Island
- Platforms
- Tracking
- Local AI
- Leaderboards
- GitHub
- LinuxDo
- System Monitor
- Terminal
- About

### 12. Updates

The app must support automatic updates for packaged releases.

Requirements:

- Sparkle-powered update checks.
- Clear "Check for Updates" action in Settings.
- Support packaged releases without changing the in-app product flow.

## Fork-Specific Omissions

This fork intentionally does not include the upstream Dictionary / Technical Terms feature. User-managed transcript terminology, its settings page, bundled term resources, and import/export workflow are out of scope for this project. Future upstream changes in that area should not be followed by default; reconsider only if this fork explicitly needs user-maintained terminology again.

## Non-Functional Requirements

- Keep the app local-first and low friction.
- Preserve stable all-time summaries.
- Keep search and scanning responsive as data grows.
- Preserve a clear boundary between shared behavior and provider-specific logic.
- Keep UI affordances compact and task-oriented.

## Explicit Future Work

- Gemini, Kimi, and MiniMax on-disk session parsing can be added later.
- New providers should enter through the provider registry and provider-specific folder.
- Any new analytics view should reuse the same local-session source of truth where possible.

## Reference Files

- `README.md`
- `.trellis/tasks/05-25-project-prd-inventory/prd.md`
- `docs/claude-statistics-inspiration-notes.md`
