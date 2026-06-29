# Lubby Bar

A tiny macOS widget that lives in your notch (or menu bar) and shows what your
coding agents are doing at a glance, plus a lightweight presence layer for the
people you wait alongside. Companion to [Lubby](https://lubby.tech).

On notched MacBooks it renders as a Dynamic-Island-style pill hugging the notch;
on every other Mac it's a normal menu-bar item.

## The status light

A single round light sits to the left of the notch, colored by your rolled-up
agent status, split proportionally when you have several sessions:

- 🟢 **green** - running
- 🟠 **orange** - waiting for your input
- 🔴 **red** - stopped

Click it and the island expands into a panel with two tabs.

### Sessions

Your live Claude Code sessions, each as a card: a status dot, the project name
(resolved from the git repo, so `…/lubby/apps/web` reads `lubby/web`), a
`RUN`/`WAIT`/`STOP` chip, and a per-second uptime. Click a card to jump straight
to that session's terminal tab. Abandoned sessions (no update for ~30 min) are
pruned automatically, and the list holds a stable order so rows don't jump
around as statuses tick.

### Lubby (social)

When you connect to a Lubby server, a second tab lights up:

- **Who's waiting nearby** right now (aggregate count, plus your top stack).
- A **People list** - your connections first, then nearby devs - each with a
  circular avatar, their **local time + offset**, a coarse location derived from
  their timezone, and a live status dot. Click someone to open their profile.
- **Pings**: someone said hi, a connection request, etc., each with its age and
  an **All →** link to the full notifications page.
- A new ping **pops a Dynamic-Island toast** from the notch, then tucks away.

Not connected yet? The Lubby tab is a one-tap **Connect** call to action.

## Two sources (pick in Settings)

- **Local** - fully offline and private. A Claude Code hook writes a small
  status file (`~/.lubby-bar/status.json`) that the app watches. No account, no
  network.
- **Lubby** - sign in to your Lubby server and the dot reflects your status as
  the server sees it (works across machines). The social tab runs whenever you
  are connected, independent of which status source you pick, so you can stay in
  Local mode and still get presence and pings. Uses the same `lub_` connector
  token as the rest of Lubby, obtained via a browser approval flow (no token
  pasting required, though you can paste one if you prefer).

## Privacy

Like the rest of Lubby, this never transmits source code, file names, paths,
prompts, terminal output, or diffs. In local mode the status file only records a
coarse status, the agent name (`claude_code`), and the project name, and it
never leaves your machine. The hook never reads the transcript. The social layer
only ever shows people's names, avatars, coarse timezone, and a coarse status,
never location coordinates.

## Install

Requires macOS 13+.

```bash
git clone https://github.com/aliwesome/lubby-bar.git
cd lubby-bar
./Scripts/build-app.sh release
open build/LubbyBar.app
```

Or grab a build from [lubby.tech/download](https://lubby.tech/download).

Then open the panel → **gear (Settings)**:

- **Local mode**: click **Install hook**. Start a Claude Code session and the
  light turns green; when Claude asks for input it turns orange; when it stops,
  red.
- **Lubby mode / social**: set your server URL (default `https://lubby.tech`),
  click **Connect to Lubby**, and approve in the browser.

Toggle **Launch at login** to keep it running.

## How local detection works

`Install hook` adds these entries to `~/.claude/settings.json` (existing hooks
are preserved):

| Claude event       | Status        |
| ------------------ | ------------- |
| `SessionStart`     | running       |
| `UserPromptSubmit` | running       |
| `PreToolUse`       | running       |
| `Notification`     | waiting input |
| `Stop`             | completed     |

`UserPromptSubmit` and `PreToolUse` are what turn the light back to green when a
new turn begins, otherwise it would stick on the previous `Stop`.

Each runs `LubbyBar hook <event>`, the same binary in CLI mode, which updates the
local status file. A running session with no update for ~30 minutes is treated as
stopped (covers crashes where no Stop hook fires).

## Develop

```bash
swift build          # compile
swift run LubbyBar    # run from source (the notch/menu-bar item appears)
```

Source lives in `Sources/LubbyBar/`. The app and the `hook` CLI share one binary;
`Entry.swift` dispatches between them. The notch window and its three states
(dot → toast → panel) live in `NotchIsland.swift` / `NotchIslandView.swift`; the
social polling in `PresenceFeed.swift`.

## License

MIT. See [LICENSE](LICENSE).
