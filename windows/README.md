# Lubby Bar for Windows

The Windows system-tray companion to [Lubby](https://lubby.tech), the Windows
sibling of the macOS notch widget. Built with **Tauri 2** (Rust + a small React
panel); the cross-platform status/hook logic lives in the `core/` crate.

> Status: local sessions are feature-complete and the `core` crate is
> unit-tested; the GUI is verified to compile and is built by CI on
> `windows-latest` (see `.github/workflows/windows.yml`). The 0.2.0 flyout
> anchoring, hide-on-blur, and single-instance fixes respond to the first
> hands-on Windows test and want that smoke test re-run to confirm. See
> `docs/windows-widget-plan.md` for the roadmap.

## What it does

- A **tray icon** colored by your rolled-up Claude Code status (green running,
  orange waiting on you, red stopped), updated as the status file changes.
- A **flyout panel** (left-click the tray icon) that opens anchored to the tray,
  shows your live sessions, and **dismisses when it loses focus**, like a native
  tray popover. Only one instance ever runs (relaunch just re-shows the panel).
- **One-click hook install** from the panel: writes
  `lubby-bar.exe hook <event>` into `~/.claude/settings.json` (idempotent, and it
  preserves any hooks you already have), so sessions start flowing without
  touching a config file. Remove it again from the footer.
- The underlying **`hook` subcommand** (`lubby-bar.exe hook <event>`) writes
  `%APPDATA%\lubby-bar\status.json` with git-repo-aware project names and a
  30-minute staleness prune. Never reads your code, prompts, or transcript.

## Layout

```
windows/
  core/        Rust lib: status file, hook, roll-up (cross-platform, unit-tested)
  src-tauri/   Tauri 2 app: tray + flyout window + the hook dispatch
  src/         React panel (Vite)
```

## Develop (on Windows)

Requires Rust, Node 18+, and the WebView2 runtime (preinstalled on Windows 11).

```powershell
cd windows
npm install
npm run tauri dev      # run the app
npm run tauri build    # produce an NSIS installer
```

Run the core tests anywhere (they need no GUI):

```bash
cargo test --manifest-path windows/core/Cargo.toml
```

## Roadmap

Next: the Connect flow and the Lubby (social) tab against the existing connector
API (mirroring the macOS browser-approval login and "reuse the plugin's
connection"); then native toasts, launch-at-login, signing, and auto-update. See
`../docs/windows-widget-plan.md`.
