# CodexSessionBar

`CodexSessionBar` is a macOS menu bar client for `codex app-server`. It keeps a long-lived app-server connection open and turns recent Codex threads into a compact, always-available mini chat surface.

## Current App Shape

The project currently ships as a single `MenuBarExtra` window on macOS 15+:

- Menu bar label shows the current live-session count.
- The main panel opens as a compact mini session window.
- The header shows the active thread title, workspace, and status.
- The `+` button starts a fresh draft thread.
- The overflow menu lets you switch between recent sessions and quit the app.
- Selecting an existing session reloads that thread and shows its latest transcript.

There is no separate session library window in the current build.

## What The Mini Session Supports

- Reading existing Codex thread history through `thread/read`.
- Switching between recent sessions returned by `thread/list`.
- Starting new threads with `thread/start`.
- Resuming inactive threads with `thread/resume`.
- Sending turns with `turn/start`.
- Streaming assistant deltas and turn lifecycle updates from the app-server event stream.
- Showing compact transcript entries for user messages, assistant messages, plans, tool activity, command execution, and other thread items that are already modeled in the payload layer.
- Changing the working directory for the current draft/session from the panel header.
- Choosing model, reasoning effort, and Fast mode from the inline composer controls.
- Persisting composer preferences in `UserDefaults`.

## Implementation Notes

- The SwiftPM package targets `macOS 15` and uses SwiftUI plus the Observation framework.
- `CodexMiniAppModel` owns session discovery, recent-session selection, polling, and app-server event handling.
- `ChatWindowModel` owns the active transcript, draft state, resume behavior, and send flow for the currently displayed route.
- `CodexAppServerClient` speaks directly to `codex app-server` over a persistent subprocess-backed RPC connection.
- The mini client currently requests threads with `approvalPolicy: never` and `sandbox: workspace-write` when starting or resuming threads.

## Running

Make sure the `codex` executable is installed and available to the app.

Run the app with:

```bash
swift run
```

`CodexSessionBar` resolves `codex` from `PATH` first, then falls back to:

- `/opt/homebrew/bin/codex`
- `/usr/local/bin/codex`
- `~/.local/bin/codex`

If `codex` cannot be found, the app surfaces an error state instead of connecting.

## Development

Build:

```bash
swift build
```

Test:

```bash
swift test
```

## Repository Layout

- [Sources/CodexSessionBar/CodexSessionBarApp.swift](Sources/CodexSessionBar/CodexSessionBarApp.swift): app entry point and menu bar extra wiring
- [Sources/CodexSessionBar/AppModel.swift](Sources/CodexSessionBar/AppModel.swift): top-level app/session state
- [Sources/CodexSessionBar/ChatWindowModel.swift](Sources/CodexSessionBar/ChatWindowModel.swift): active session model and send/resume logic
- [Sources/CodexSessionBar/CodexAppServerClient.swift](Sources/CodexSessionBar/CodexAppServerClient.swift): app-server transport and RPC layer
- [Sources/CodexSessionBar/MenuSessionPanel.swift](Sources/CodexSessionBar/MenuSessionPanel.swift): compact menu panel composition
- [Sources/CodexSessionBar/MiniSessionComposer.swift](Sources/CodexSessionBar/MiniSessionComposer.swift): model/reasoning/fast controls and message input
- [Sources/CodexSessionBar/Models.swift](Sources/CodexSessionBar/Models.swift): decoded Codex thread, turn, and transcript item models
