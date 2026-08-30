# AI Usage

A menu bar / system tray app for watching your AI coding quotas — Claude Code,
Antigravity, Codex and Cursor — without opening a browser or burning a prompt
to ask.

**Download:**

| Platform | Link | Built from |
|----------|------|------------|
| macOS (Apple Silicon) | [AI-Usage.dmg](https://github.com/eli-manning/Ai-Usage/releases/latest/download/AI-Usage.dmg) | `mac-native/` — native Swift |
| Windows | [Claude-Tray.exe](https://github.com/eli-manning/Ai-Usage/releases/latest/download/Claude-Tray.exe) | `os-menu/` — Electron |

macOS runs a native Swift rebuild: one process, no Electron, no Node, no
python3. Windows runs the original Electron app, which is still the only
implementation for that platform.

> **First launch:** the app is unsigned, so macOS will refuse to open it.
> After dragging it to Applications, go to **System Settings → Privacy &
> Security**, scroll down, and click **Open Anyway**. If macOS instead says the
> app *"is damaged and can't be opened"*, run
> `xattr -cr "/Applications/AI Usage.app"` in Terminal and launch it again.
> Signing this properly needs a paid Apple Developer ID, which this project
> doesn't have.

## Two ways to display it

macOS only, since both depend on Mac hardware and AppKit. Pick either in
Settings; switching is instant and doesn't re-fetch.

- **Menu bar** — a coloured badge showing the current percentage, click for a
  popover with gauges, reset times and a history chart.
- **Notch** — a panel fused to the notch on Apple Silicon MacBooks. At rest
  it's a slim bar with a live readout; hover and it expands into a radial ring
  of provider wedges.

Right-click the badge (or the notch hub) for Refresh, Settings, the setup
wizard, and Quit.

## Requirements

macOS 13+, and whichever provider CLIs you want tracked, installed and signed
in:

| Provider | CLI |
|----------|-----|
| Claude | `npm i -g @anthropic-ai/claude-code` |
| Antigravity | `agy` |
| Codex | `codex` |
| Cursor | `cursor-agent` |

Providers you don't have are simply switched off in Settings.

## Privacy

Everything runs locally. The app shells out to the provider CLIs already
installed on your machine and reads their output — no API calls, no
credentials, no network traffic beyond what those CLIs make themselves.
History is a JSON file in `~/Library/Application Support/AiUsage/`.

## Building from source

```sh
cd mac-native
make app     # assemble build/AI Usage.app
make run     # assemble and launch it
make test    # unit + parser-equivalence tests
make dist    # dist/AI-Usage.dmg and dist/AI-Usage.zip
```

`make debug` runs straight from SwiftPM, which is the fastest loop for popover
and settings work — but the menu bar item and login-item registration need the
real bundle that `make app` produces.

## Chrome extension

A separate tool, in `chrome-extension/`, for **Claude.ai** — the web app rather
than the CLI. Session and weekly gauges, a history chart and threshold alerts,
in a browser popup. It shares nothing with the desktop apps above; it reads the
web app directly.

Not on the Web Store — load it unpacked:

1. Open Chrome → `chrome://extensions`
2. Enable **Developer mode** (top right)
3. **Load unpacked** → select `chrome-extension/`

→ [Details](chrome-extension/README.md)

## Layout

```
mac-native/     the macOS app — Swift, no Electron, no Node, no python3
  Sources/UsageCore/    parsing, models, provider drivers, refresh loop
  Sources/AiUsage/      status item, popover, notch panel, settings, wizard
  Sources/ptydrive/     PTY helper that drives the provider CLIs
os-menu/        the Electron app, still what Windows ships
chrome-extension/  the Claude.ai browser extension
scripts/        the original JavaScript fetchers, kept as the reference
                implementation the Swift parsers are tested against
```

`UsageCore` is deliberately free of AppKit and SwiftUI so the parsers can be
tested headlessly. `ParserEquivalenceTests` runs them against a fixture corpus
captured from the real CLIs, so provider output drifting is caught by the test
suite rather than by a user seeing a blank badge.

`ptydrive` is a separate executable rather than code inside the app because
`fork()` in a process that has already started AppKit's threads isn't
async-signal-safe; keeping fork/exec in a single-threaded helper sidesteps it.

## Releases

Tagging is what publishes:

```sh
git tag v1.1.0
git push --tags
```

`.github/workflows/release.yml` then builds both platforms in parallel — the
Swift app on a macOS runner, the Electron installer on a Windows one — verifies
each artifact, and a final job attaches all three files to a single GitHub
release. The tag is the source of truth for the version, stamped into the macOS
bundle's `Info.plist` and the Electron `package.json` alike.

Ordinary pushes run `ci.yml` instead, which tests and validates without
publishing anything.

### Building the Windows installer locally

```sh
cd os-menu
npm install
npm run build:win   # dist/Claude-Tray.exe
```

Requires Windows, or Wine on macOS/Linux.

## History

This project was previously split across two repositories. The Electron app,
the Chrome extension and the release pipeline lived in `claude-usage-tracker`,
while the native rewrite was developed here. Everything now lives in this repo;
`claude-usage-tracker` is retired.

## License

Apache 2.0 — see [LICENSE](LICENSE).
