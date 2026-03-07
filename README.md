# CodexSessionBar

A macOS menu bar app that keeps a long-lived `codex app-server` connection open and tracks Codex sessions from `thread/list`.

## Features

- Menu bar item with a count of live sessions, or tracked recent sessions when none are live.
- Long-lived app-server connection with `initialize` followed by `initialized`.
- Event-driven refreshes when the app-server emits thread or turn lifecycle notifications, with 8-second polling as a backstop.
- Session details: preview, source, model provider, working directory, update time.
- Session activity tag derived from the thread runtime status returned by `thread/list`.
- Quick actions per session:
  - Open working directory
  - Copy session ID
  - Reveal thread file (when available)
- Dedicated tracker window for easier monitoring.

## Notes

- `thread/list` is requested with explicit `sourceKinds` so CLI, VS Code, app-server, exec, and sub-agent threads are included.
- The app uses the thread runtime `status` from `thread/list` instead of `thread/loaded/list`, which avoids treating connection-local loaded state as global activity.

## Run

```bash
swift run
```

The app resolves `codex` from `PATH` first, then tries:
  - `/opt/homebrew/bin/codex`
  - `/usr/local/bin/codex`
  - `~/.local/bin/codex`
If Codex is not found, the app shows an error in the menu and tracker window.
