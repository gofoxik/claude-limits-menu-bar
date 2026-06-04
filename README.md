# Claude Limits — macOS Menu Bar

A tiny native macOS menu bar app that shows your **Claude Code usage limits** as a circular
progress ring — the same numbers the CLI's `/usage` command displays, always visible.

<!-- Add a screenshot here -->

## Features

- **Live ring** in the menu bar tracking your current 5-hour session limit (blue → orange → red as it fills).
- **Dropdown with progress bars** for the 5-hour session and weekly windows, like Claude Code's `/usage`.
- **No separate login** — reuses the OAuth token Claude Code already stored in your macOS
  Keychain, and refreshes it automatically. Works even when no `claude` session is running.
- Refreshes itself every few minutes (with rate-limit-aware backoff).
- **Launch at Login** toggle.

## Requirements

- macOS 13+
- Swift toolchain (Xcode or Command Line Tools)
- A signed-in Claude Code CLI on the same Mac (the app reads its Keychain credentials)

## Build & run

```sh
./build.sh
open "build/Claude Limits.app"
```

`build.sh` runs `swift build -c release` and packages the result into `build/Claude Limits.app`
(an accessory app — no Dock icon). Open the dropdown and toggle **Launch at Login** to keep it
running across reboots.

## How it works

1. Reads the OAuth token from the macOS Keychain entry `Claude Code-credentials`.
2. Calls `GET https://api.anthropic.com/api/oauth/usage` (the endpoint behind `/usage`).
3. Refreshes the token when it expires and writes it back to the same Keychain entry, so the
   CLI and this app share a single login.

See [`CLAUDE.md`](CLAUDE.md) for architecture details.

## Notes

- Relies on a private OAuth endpoint that Anthropic may change; the app degrades to a clear
  error state rather than crashing.
- The usage endpoint rate-limits aggressively, so polling is intentionally gentle.
