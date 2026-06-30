# Lubby Bar for Windows

The Windows system-tray companion to [Lubby](https://lubby.tech), the Windows
sibling of the macOS notch widget. Built with **Tauri 2** (Rust + a small React
panel); the cross-platform status/hook logic lives in the `core/` crate.

> Status: Phase 1 scaffold. The `core` crate is unit-tested and the Tauri app
> compiles; the full Windows app is built and verified by CI on `windows-latest`
> (see `.github/workflows/windows.yml`). See `docs/windows-widget-plan.md` for the
> roadmap.

## What it does (Phase 1)

- A **tray icon** colored by your rolled-up Claude Code status (green running,
  orange waiting on you, red stopped), updated as the status file changes.
- A **flyout panel** (left-click the tray icon) showing your live sessions, the
  same status, project names, and chips as the macOS widget.
- A **`hook` subcommand** (`lubby-bar.exe hook <event>`) that Claude Code calls,
  it writes `%APPDATA%\lubby-bar\status.json` with git-repo-aware project names
  and a 30-minute staleness prune. Never reads your code, prompts, or transcript.

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

Phase 2 adds the Connect flow and the Lubby (social) tab against the existing
connector API; Phase 3 adds native toasts, launch-at-login, signing, and
auto-update. See `../docs/windows-widget-plan.md`.
