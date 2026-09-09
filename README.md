# AI Usage

A menu bar / system tray app for watching your AI coding quotas — Claude Code,
Antigravity, Codex and Cursor — without opening a browser or burning a prompt
to ask.

## Install

**macOS (Apple Silicon)** — Homebrew:

```sh
brew install eli-manning/tap/ai-usage
```

Or download [AI-Usage.dmg](https://github.com/eli-manning/Ai-Usage/releases/latest/download/AI-Usage.dmg) and drag it to Applications.

**Windows** — download [Claude-Tray.exe](https://github.com/eli-manning/Ai-Usage/releases/latest/download/Claude-Tray.exe).

| Platform | Built from |
|----------|------------|
| macOS (Apple Silicon) | `mac-native/` — native Swift |
| Windows | `os-menu/` — Electron |

macOS runs a native Swift rebuild: one process, no Electron, no Node, no
python3. Windows runs the original Electron app, which is still the only
implementation for that platform — and tracks all four providers there, via
node-pty's ConPTY rather than the POSIX-only `*-pty-wrapper.py` scripts.

> **First launch:** the app is ad-hoc signed rather than notarized, so macOS
> will refuse to open it the first time — however you installed it, Homebrew
> included. Go to **System Settings → Privacy & Security**, scroll down, and
> click **Open Anyway**. If macOS instead says the app *"is damaged and can't
> be opened"*, run `xattr -cr "/Applications/AI Usage.app"` in Terminal and
> launch it again. Signing this properly needs a paid Apple Developer ID,
> which this project doesn't have.

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

macOS 13+ on Apple Silicon (the released bundle is arm64), and whichever
provider CLIs you want tracked, installed and signed in:

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
make icons   # re-render the app icons (only when the artwork changes)
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
os-menu/        the Electron app, still what Windows ships, and the
                JavaScript parsers the Swift ones are tested against
chrome-extension/  the Claude.ai browser extension
```

`UsageCore` is deliberately free of AppKit and SwiftUI so the parsers can be
tested headlessly. `ParserEquivalenceTests` runs them against a fixture corpus
captured from the real CLIs, so provider output drifting is caught by the test
suite rather than by a user seeing a blank badge. `make verify` goes further
and diffs the Swift parsers against `os-menu`'s JavaScript originals on the
same fixtures — the two implementations have to agree.

`ptydrive` is a separate executable rather than code inside the app because
`fork()` in a process that has already started AppKit's threads isn't
async-signal-safe; keeping fork/exec in a single-threaded helper sidesteps it.

Both apps' icons come from one renderer, `mac-native/scripts/make-icon.swift` —
`make icons` writes the macOS `.icns` and the PNG electron-builder turns into
the Windows `.ico`, so the two platforms can't drift apart visually. The
outputs are committed; neither build regenerates them.

### Driving the CLIs

Every provider is driven the same way — launch its CLI in a pseudo-terminal,
wait for the ready prompt, type its usage command, wait for the quota panel to
actually paint, capture the screen — and that drive spec exists three times:

| Where | Implementation |
|-------|----------------|
| The native macOS app | `mac-native/Sources/UsageCore/PTYSession.swift` |
| Electron on macOS/Linux | `os-menu/*-pty-wrapper.py` |
| Electron on Windows | `os-menu/win-pty-driver.js` (node-pty / ConPTY) |

None of the three may drift: `mac-native`'s `ParserEquivalenceTests` and
`os-menu`'s `npm test` are what hold them to the same numbers and markers.

A signed-out CLI is never re-driven by the background poll, on either platform.
Launching one isn't a no-op — `agy`, `codex` and `cursor-agent` all answer by
opening a browser tab for their OAuth handoff, which can't be completed because
the code has to be pasted back into a terminal the user can't see. Only an
explicit Refresh tries again.

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

### The Homebrew cask

The cask lives in [eli-manning/homebrew-tap](https://github.com/eli-manning/homebrew-tap)
and pins the release asset by hash, so it has to be bumped after every tag or
`brew install` keeps handing people the previous version. `release.yml`'s
`bump-cask` job does it automatically, given a `TAP_GITHUB_TOKEN` secret — a
PAT with `contents: write` on the tap repo, since `GITHUB_TOKEN` only reaches
this one. Without the secret the job logs a notice and skips, and the bump is
two lines by hand:

```sh
shasum -a 256 AI-Usage.zip          # from the new release's assets
# edit Casks/ai-usage.rb: version + sha256, then
brew style --cask Casks/ai-usage.rb
```

### Building the Windows installer locally

```sh
cd os-menu
npm ci
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
