# Plan: Lubby Bar for Windows

A Windows companion to the macOS notch widget. Windows has no notch, so the
natural home is the **system tray (notification area)**: a small status icon that
changes color with your agent status and opens a flyout panel, mirroring the
macOS island's dot → toast → panel model.

## Goal / parity

Reach feature parity with the macOS app, reusing the same server contract:

- A **tray icon** colored by rolled-up agent status (green/orange/red), split for
  multiple sessions where feasible.
- A **flyout panel** (anchored above the tray icon) with the same two tabs:
  - **Sessions** - live Claude Code sessions (status, git-repo project name,
    chip, uptime, click-to-focus the terminal).
  - **Lubby** - presence + People list (connections + nearby, avatar, local
    time/offset, status), pings, and a Connect CTA when signed out.
- **Toast notifications** for new pings via native Windows toasts.
- **Local** (hook + status file) and **Lubby** (connector token) sources, exactly
  as on macOS.

The server side already exists and is shared: `/api/me/sessions`,
`/api/me/notifications`, `/api/me/people`, `/api/presence/waiting`, the `lub_`
connector token, and the device-login flow. **No server changes are required.**

## Recommended stack: Tauri 2 (Rust + web UI)

Why Tauri over WPF/WinUI or Electron:

- Tiny binary, low memory, native tray + global flyout window support.
- The team is web-first (React/Laravel); the flyout UI can be built in React and
  shares design tokens with lubby.tech (Campfire palette, dark mode).
- Rust handles the parts that must be native: the tray icon (dynamic colored
  image), the `hook` CLI subcommand, watching the status file, HTTP polling, the
  keychain-equivalent (Windows Credential Manager), and toast notifications.
- One codebase could later target Linux too.

(Alternative if a pure-native team prefers it: **.NET 8 + WinUI 3 / WPF** with
`NotifyIcon`, `H.NotifyIcon`, and `CommunityToolkit` for toasts. More Windows-
idiomatic, more code, no UI reuse.)

## Architecture

```
lubby-bar-win/
  src-tauri/            # Rust
    main.rs             # tray, flyout window, single-instance
    hook.rs             # `lubby-bar.exe hook <event>` CLI (mirrors HookCLI.swift)
    status_file.rs      # %APPDATA%\lubby-bar\status.json read/write + prune
    feed.rs             # connector polling (sessions/notifications/people/nearby)
    creds.rs            # Windows Credential Manager (token store)
    toast.rs            # Windows toast notifications for pings
    tray.rs             # dynamic colored tray icon
  src/                  # React flyout UI (Sessions + Lubby tabs, panel)
```

### Tray icon + flyout

- One process, single-instance (so `hook` invocations and the UI don't collide;
  the hook path exits fast and just writes the file).
- The tray icon is a generated PNG/ICO tinted by status; regenerate on change.
  Multi-session "proportional" coloring is nice-to-have; v1 can use the rolled-up
  status color.
- Left-click toggles a borderless, always-on-top flyout window positioned just
  above the tray icon (bottom-right of the primary screen, respecting the
  taskbar). Dismiss on focus-loss (like the macOS outside-click).

### The hook CLI

- Claude Code hooks run commands on Windows too (`~/.claude/settings.json`,
  same JSON shape). `Install hook` writes the same five events
  (SessionStart/UserPromptSubmit/PreToolUse → running, Notification → waiting,
  Stop → completed), each calling `lubby-bar.exe hook <event>`.
- The hook reads the small JSON Claude pipes on stdin (`session_id`, `cwd`),
  resolves the git repo name (run `git -C <cwd> rev-parse --show-toplevel` once
  per new session), and upserts `%APPDATA%\lubby-bar\status.json` with the same
  shape and 30-minute staleness pruning.
- Windows has no controlling tty; the "jump to terminal" affordance degrades to
  "open the project folder" (or focus the owning console window via its PID if
  we capture it). Keep the field optional, as macOS already does.

### Sources, feed, and social layer

- **Local**: watch the status file (debounced), roll up the status exactly like
  `LocalSource`, prune stale rows, stable sort by project.
- **Lubby/social**: poll the four connector endpoints every ~15 s whenever a
  token exists (independent of source), mirroring `PresenceFeed` and the
  first-poll "toast only the last few minutes" rule. Remote avatars via the
  webview's `<img>`; local time/offset/place derived from the IANA timezone
  string client-side, same helpers as the macOS app.
- **Token**: store in Windows Credential Manager; obtain via the existing browser
  device-login (open the verification URL, poll the claim endpoint).

### Toasts

- New ping → a native Windows toast ("👋 Sara said hi") whose activation opens
  the ping URL. Respect the same first-poll suppression of the backlog.

## Distribution

- Ship an MSI/NSIS installer (Tauri bundler) and a portable `.exe`.
- Code-sign to avoid SmartScreen warnings (EV or standard cert).
- Auto-update via Tauri's updater pointed at GitHub Releases.
- Surface it on `lubby.tech/download` alongside the macOS build (the download
  page should detect the OS and lead with the matching button).

## Phasing

1. **Tray + local status** - tray icon color + flyout Sessions tab from the
   status file; the `hook` CLI + installer. (Offline parity.)
2. **Connect + Lubby tab** - device login, connector polling, People list,
   pings feed.
3. **Toasts + polish** - native toasts, launch-at-login, auto-update, signing.

## Open questions

- Multi-monitor / taskbar-position handling for the flyout anchor.
- Whether to attempt the proportional multi-session tray icon on day one.
- Console-window focusing for "jump to terminal" vs just opening the folder.
