# CodexSessionBar

A macOS menu bar app that uses `codex app-server` to track Codex sessions from `thread/list`, with `thread/loaded/list` used to mark currently loaded ones.

## Features

- Menu bar item with live count of loaded sessions (or tracked recent sessions when none are loaded).
- Auto-refresh every 8 seconds.
- Session details: preview, source, model provider, working directory, update time.
- Session activity tag: `Loaded` or `Recent`.
- Quick actions per session:
  - Open working directory
  - Copy session ID
  - Reveal thread file (when available)
- Dedicated tracker window for easier monitoring.

## Run

```bash
swift run
```

## Notes

- The app resolves `codex` from `PATH` first, then tries:
  - `/opt/homebrew/bin/codex`
  - `/usr/local/bin/codex`
  - `~/.local/bin/codex`
- If Codex is not found, the app shows an error in the menu and tracker window.
