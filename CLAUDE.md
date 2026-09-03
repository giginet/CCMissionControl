# CCMissionControl

## Build & Test

```bash
# Build
xcodebuild -scheme CCMissionControl -configuration Debug build

# Run unit tests only (skip UI tests)
xcodebuild test -scheme CCMissionControl -configuration Debug -destination 'platform=macOS' -only-testing:CCMissionControlTests
```

## Architecture

macOS menu bar app (SwiftUI) that detects running Claude Code sessions via WezTerm CLI and system process inspection.

### Key layers

- **Models/** — `Agent`, `WezTermPane`, `WezTermClient`, `ProcessEntry`
- **Services/** — `AgentScanner` (scan logic, WezTerm/ps cross-referencing), `ShellExecutor` (subprocess runner), `FloatingPanelController` (panel per `WindowMode`), `WezTermWindowLocator` (WezTerm window frame via CGWindowList)
- **Views/** — `AgentRowView`, `StatusBadge`
- **ContentView.swift** — `AgentListViewModel` (@Observable, timer-based scan) and main view
- **CCMissionControlApp.swift** — `MenuBarExtra` entry point and menu bar label

### Scan algorithm

1. `wezterm cli list --format json` — get panes
2. `wezterm cli list-clients --format json` — get `focused_pane_id`
3. `/bin/ps -eo pid,ppid,tty,comm` — get process tree
4. Cross-reference TTYs to find Claude processes via ancestor chain walk
5. Detect running/idle via `caffeinate` child process

### Important notes

- App Sandbox is **disabled** (`ENABLE_APP_SANDBOX = NO`) — required for subprocess execution
- WezTerm CLI is invoked via full path (`/Applications/WezTerm.app/Contents/MacOS/wezterm`), not via shell, because the app doesn't inherit the user's PATH
- `ps` output has double spaces before the COMM column — command string must be trimmed
- `ShellExecutor` reads pipe data **before** `waitUntilExit()` to avoid pipe buffer deadlock
- `is_active` from `wezterm cli list` only indicates pane selection within a tab, not tab visibility. Use `focused_pane_id` from `list-clients` for actual focus detection
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` is enabled — service layer methods must be `nonisolated`
- `WindowMode.followWezTerm` snaps the panel to the left of the frontmost WezTerm window (same height) via a 30 Hz timer, and keeps it at `.normal` level directly above WezTerm in z-order via `NSWindow.order(.above, relativeTo:)` (works across apps). It is a no-op while WezTerm is full screen
- `CGWindowListCopyWindowInfo` bounds may be reported in a uniformly scaled/offset space on some display setups (observed 0.9x, centered). `WezTermWindowLocator` calibrates the mapping using our own panel's known AppKit frame — do not assume a plain y-flip
