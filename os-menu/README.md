# AI Usage — Electron (`os-menu/`)

The Electron implementation, and what **Windows** ships. macOS has a native
Swift rebuild in [`mac-native/`](../mac-native) instead — see the
[repository README](../README.md) for downloads.

Tracks four providers: Claude Code, Antigravity, Codex and Cursor. Each is
driven by launching its CLI in a pseudo-terminal, typing its usage command, and
parsing the screen that comes back.

## Download

The Windows installer is attached to every release:
[AI-Usage-Setup.exe](https://github.com/eli-manning/Ai-Usage/releases/latest/download/AI-Usage-Setup.exe).

Upgrading from **Claude Tray**, which is what this app was called before
v2.0.1? Uninstall that first — Windows keys an installed program on its name,
so it treats the two as unrelated and leaves you with both.

It installs for your user account (no admin required) and launches
automatically. The icon appears in the system tray at the bottom right; if it's
hidden, click **^** and drag it into the visible area.

## Requirements

Whichever provider CLIs you want tracked, installed and signed in. Providers
you don't have are switched off in Settings.

On macOS and Linux the four `*-pty-wrapper.py` scripts drive the CLIs, so
`python3` has to be on your PATH. Windows takes the `win-pty-driver.js` path
instead — node-pty's ConPTY, bundled with the app — and needs nothing extra.

## How a fetch works

Each provider gets a *drive spec*: the command to type, the marker that says
the prompt is ready, the marker that says the quota panel has painted, and a
timeout ladder. Three implementations share that one table, and they have to
agree:

| Where | What drives the CLI |
|-------|--------------------|
| macOS, Linux | `pty-wrapper.py`, `agy-pty-wrapper.py`, `codex-pty-wrapper.py`, `cursor-pty-wrapper.py` |
| Windows | `win-pty-driver.js` (node-pty / ConPTY) |
| The native macOS app | `mac-native/Sources/UsageCore/PTYSession.swift` |

Waiting for the panel marker rather than for a quiet screen is the part that
matters: a cold session has a real network round trip between the command
running and the quota panel painting, and a second of terminal silence lands
right inside it.

## Build from source

```bash
cd os-menu
npm ci
npm start            # run it
npm test             # the Windows PTY driver's state machine

npm run build:win    # → dist/AI-Usage-Setup.exe   (needs Windows, or Wine)
npm run build:mac    # → dist/AI-Usage.dmg          (superseded by mac-native/)
npm run build:linux  # → dist/AI-Usage.AppImage
```

The app icon is generated, not hand-drawn — `build/icon.png` comes from
`mac-native/scripts/make-icon.swift` via `make icons`, so the tray app and the
native app can't drift apart visually.

## Troubleshooting

**Blank tray icon, or "Could not run claude"**
The CLI isn't on your PATH. Run `where claude` (Windows) or `which claude`
(macOS). If it's missing: `npm i -g @anthropic-ai/claude-code`.

**A provider is stuck showing "not signed in"**
Sign in from a real terminal — `claude`, `agy`, `codex` or `cursor-agent` — and
then hit Refresh. The app deliberately stops re-launching a signed-out CLI on
its own five-minute poll: these CLIs answer being launched by opening a browser
tab for their OAuth handoff, and the code has to be pasted back into a terminal
you can actually see, so polling one would just spawn a dead-end tab every five
minutes.

**Stuck on "fetching…" only in the installed app**
Claude Code is showing its directory-trust prompt. Run it once by hand:
`cd ~ && claude /usage` (macOS) or `cd %USERPROFILE% && claude /usage`
(Windows), and press **Enter** at the prompt.

**Debug log**
Source builds (`npm start`) write to `~/ai-usage-debug.log`. Packaged builds
write nothing.
