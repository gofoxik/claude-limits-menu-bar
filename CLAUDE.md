# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A native macOS menu bar app (`Claude Limits.app`) that displays Claude Code's usage limits
as a circular progress ring — the same data the CLI's `/usage` command shows. It's a
SwiftPM executable with no third-party dependencies (Foundation + AppKit + Security +
ServiceManagement only). Runs as an accessory app (no Dock icon).

## Commands

- **Build + package into `.app`:** `./build.sh` → produces `build/Claude Limits.app` (runs
  `swift build -c release`, assembles the bundle with an `LSUIElement` Info.plist, ad-hoc codesigns).
- **Compile only:** `swift build -c release`
- **Run:** `open "build/Claude Limits.app"` (after building)
- **Restart during dev:** `pkill -f ClaudeLimitsMenuBar; ./build.sh; open "build/Claude Limits.app"`
- **Read app logs (errors are `NSLog`'d with prefix `ClaudeLimits:`):**
  `log show --predicate 'process == "ClaudeLimitsMenuBar"' --last 2m --style compact`

There are no tests and no linter configured.

## How it connects to the account (the core mechanism)

The app does **not** implement its own login. It reuses the OAuth token Claude Code already
stored in the macOS Keychain (generic-password service `Claude Code-credentials`, JSON
`{claudeAiOauth:{accessToken, refreshToken, expiresAt(ms), ...}}`). Flow:

1. `Credentials.load()` reads/decodes the Keychain entry.
2. `Credentials.validToken()` refreshes via `POST https://platform.claude.com/v1/oauth/token`
   when `expiresAt` is near, then **writes the new token back to the same Keychain entry** —
   this is deliberate so the CLI and app share one login and never diverge.
3. `UsageClient.fetch()` calls `GET https://api.anthropic.com/api/oauth/usage` with headers
   `Authorization: Bearer`, `anthropic-beta: oauth-2025-04-20`, `anthropic-version: 2023-06-01`.
   Response has `five_hour` / `seven_day` / `seven_day_opus` / `seven_day_sonnet`, each
   `{utilization 0-100, resets_at}`. Per-model weekly windows are `null` on Pro plans, and
   the UI skips null windows.

## Architecture (`Sources/ClaudeLimitsMenuBar/`)

- `main.swift` — bootstraps `NSApplication` as `.accessory`, owns the single `StatusController`.
- `Credentials.swift` — Keychain read/refresh/write-back (Security framework).
- `UsageClient.swift` + `UsageModel.swift` — the usage fetch, decode, and Codable models;
  retries once on 401 (forced refresh), surfaces 429 as `UsageError.rateLimited(retryAfter:)`.
- `RingImage.swift` — draws the menu-bar arc NSImage; `color(for:)` is the single source of
  truth for the blue/orange/red tiers (shared by the ring and the dropdown bars).
- `UsageRowView.swift` — custom flipped NSView for a dropdown row (title + % + progress bar + reset caption).
- `StatusController.swift` — owns the `NSStatusItem`, builds the menu, and runs the refresh loop.

## Critical constraint: the usage endpoint rate-limits hard

`/api/oauth/usage` returns `429 Retry-After: ~49s` after only a few requests, and probing
while limited keeps re-extending the window. The refresh strategy in `StatusController` is
built around this and must be preserved:

- Poll on a **3-minute** timer (`refreshInterval`), not seconds.
- Refresh-on-menu-open is throttled (`menuOpenMinInterval`, 90s) — don't fetch on every open.
- `isFetching` guards against overlapping requests; `rateLimitedUntil` suppresses automatic
  fetches during backoff; only user-initiated "Refresh now" passes `force: true`.
- On 429, a one-shot `retryTimer` auto-retries just after `Retry-After`.
- On any error, the last good reading stays on screen (`lastGoodUsage`) instead of blanking.

When debugging, **do not loop `curl` against the endpoint** — one stray burst locks you (and
the running app) out for ~a minute.
