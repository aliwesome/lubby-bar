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
