# Changelog

All notable changes to Lubby Bar are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- Sessions are now always read from this device's local Claude hook. The
  "Local vs Lubby" source picker is gone: the status dot and Sessions tab always
  reflect what is running on this machine. Connecting to Lubby no longer changes
  where sessions come from, it only powers the social layer (nearby presence,
  people, and pings). This matches the Windows build, which was already
  local-only, and removes the dependency on the server's `/api/me/sessions`.

### Removed

- `LubbySource` (the `/api/me/sessions` poller) and the Settings source picker.

## [0.2.0] - 2026-07-01 (Windows)

Fixes everything the first hands-on Windows test surfaced. Windows app only;
the macOS app is unchanged.

### Added

- One-click **hook install/remove** in the panel: a first-run "Connect Claude
  Code" card installs `lubby-bar.exe hook <event>` entries into
  `~/.claude/settings.json` (idempotent, preserving any hooks you already have),
  and a footer control removes them again. The install logic lives in the
  cross-platform `core` crate with unit tests.
- A single-instance guard: relaunching the app re-shows the existing panel
  instead of spawning a second tray icon.

### Fixed

- The tray flyout now opens anchored to the tray icon instead of the top-left
  corner. It anchors to the icon's own bounds (so keyboard activation via
  Win+B works too), picks the monitor under the anchor, and clamps to that
  monitor's work area, so it stays on-screen and clear of the taskbar on any
  edge, any monitor, and any DPI scale.
- The flyout dismisses on focus loss like a native tray popover, and clicking
  the tray icon while it is open closes it instead of blinking it shut and
  instantly reopening.

### Changed

- Privacy: `status.json` now holds only the coarse fields the README promises
  (status, agent, project name, timestamp). The working directory is still used
  to derive the project name but is no longer written to disk, and the
  `TERM_PROGRAM` capture is gone.

## [0.1.0] - 2026-06-24

### Added

- macOS menu-bar / notch widget showing Claude Code status as a colored dot
  (green running, orange waiting for input, red stopped, gray idle), with a
  Dynamic-Island-style panel.
- Sessions tab: per-session rows with stable ordering and automatic pruning of
  sessions idle for ~30 minutes.
- Lubby (social) tab: nearby presence, a People list (connections first, then
  nearby) with local time and coarse location, and pings that pop a toast.
- Local Claude Code hook installer and browser-approval sign-in for Lubby.
- Windows build (Tauri 2) sharing the same status-file contract.
