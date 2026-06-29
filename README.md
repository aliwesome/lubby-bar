# Lubby Bar

A tiny macOS menu-bar app that shows your Claude Code status at a glance:

- 🟢 **green** - running
- 🟠 **orange** - waiting for your input
- 🔴 **red** - stopped

It sits in the menu bar (next to the notch on notched MacBooks, in the normal
menu bar on every other Mac). Companion to [Lubby](https://lubby.tech).

## Two sources (pick in Settings)

- **Local** - fully offline and private. A Claude Code hook writes a small
  status file (`~/.lubby-bar/status.json`) that the app watches. No account, no
  network.
- **Lubby** - sign in to your Lubby server and the dot reflects your status as
  the server sees it (works across machines). Uses the same `lub_` connector
  token as the rest of Lubby, obtained via a browser approval flow (no token
  pasting required, though you can paste one if you prefer).

## Privacy

Like the rest of Lubby, this never transmits source code, file names, paths,
prompts, terminal output, or diffs. In local mode the status file only records a
coarse status, the agent name (`claude_code`), and the project folder name, and
it never leaves your machine. The hook never reads the transcript.

## Install

Requires macOS 13+.

```bash
git clone https://github.com/aliwesome/lubby-bar.git
cd lubby-bar
./Scripts/build-app.sh release
open build/LubbyBar.app
```

Then open the menu-bar icon → **Settings**:

- **Local mode**: click **Install hook**. Start a Claude Code session and the
  dot turns green; when Claude asks for input it turns orange; when it stops, red.
- **Lubby mode**: set your server URL (default `https://lubby.tech`), click
  **Connect to Lubby**, and approve in the browser.

Toggle **Launch at login** to keep it running.

## How local detection works

`Install hook` adds three entries to `~/.claude/settings.json` (existing hooks
are preserved):

| Claude event       | Status        |
| ------------------ | ------------- |
| `SessionStart`     | running       |
| `UserPromptSubmit` | running       |
| `PreToolUse`       | running       |
| `Notification`     | waiting input |
| `Stop`             | completed     |

`UserPromptSubmit` and `PreToolUse` are what turn the dot back to green when a
new turn begins, otherwise it would stick on the previous `Stop`.

Each runs `LubbyBar hook <event>`, the same binary in CLI mode, which updates the
local status file. A running session with no update for ~30 minutes is treated as
stopped (covers crashes where no Stop hook fires).

## Develop

```bash
swift build          # compile
swift run LubbyBar    # run from source (menu-bar item appears)
```

Source layout lives in `Sources/LubbyBar/`. The app and the `hook` CLI share one
binary; `Entry.swift` dispatches between them.

## License

MIT. See [LICENSE](LICENSE).
