// Windows counterpart to the *-pty-wrapper.py drivers.
//
// The Python wrappers are POSIX-only — `import pty` doesn't exist on Windows,
// and neither does the `python3` they were spawned as. Before this file,
// `runAgyCommand`/`runCodexCommand`/`runCursorCommand` spawned them anyway, so
// three of the four providers could never report anything on the platform this
// app actually ships to; only Claude had a ConPTY path.
//
// The wrappers are identical apart from a handful of constants, so this is one
// driver parameterised by that table rather than three near-copies. The state
// machine below is a direct transcription of the loop in agy-pty-wrapper.py
// (which is also what mac-native's PTYSession.DriveSpec ports), so the two
// platforms drive each CLI the same way and the shared parsers keep working.
const fs = require("fs");
const os = require("os");

// One entry per PTY-driven provider. Field-for-field the constants at the top
// of each wrapper — see PTYSession.swift's `spec(for:)` for the same table.
const SPECS = {
  antigravity: {
    args: [],
    typedCommand: "/usage",
    readyMarker: "for shortcuts",
    panelMarker: "GEMINI MODELS",
    idleQuietMs: 1000,
    panelFallbackMs: 10000,
    totalTimeoutMs: 55000,
    // First-run onboarding blocks the ready prompt; Enter accepts the
    // defaults. Only agy needs it, and only once per machine.
    wizardNudgeMs: 35000,
    wizardNudgeIntervalMs: 1200,
  },
  codex: {
    args: [],
    typedCommand: "/status",
    readyMarker: "to change",
    panelMarker: "Account:",
    idleQuietMs: 1000,
    panelFallbackMs: 10000,
    totalTimeoutMs: 20000,
    wizardNudgeMs: 0,
    wizardNudgeIntervalMs: 1200,
  },
  cursor: {
    args: ["--trust"],
    typedCommand: "/usage",
    readyMarker: "Auto",
    panelMarker: "Esc to close",
    idleQuietMs: 1200,
    panelFallbackMs: 10000,
    totalTimeoutMs: 25000,
    wizardNudgeMs: 0,
    wizardNudgeIntervalMs: 1200,
  },
};

// `where` hands back the POSIX shell-script variant of an npm-installed CLI
// first, which ConPTY can't launch — the `.cmd` batch shim beside it is what
// actually starts the program. Same fix the Claude path in main.js needed.
function resolveLaunchable(binaryPath) {
  const clean = String(binaryPath).replace(/[\r\n]+$/, "");
  const lower = clean.toLowerCase();
  if (lower.endsWith(".cmd") || lower.endsWith(".exe") || lower.endsWith(".bat")) return clean;
  for (const ext of [".cmd", ".exe", ".bat"]) {
    if (fs.existsSync(clean + ext)) return clean + ext;
  }
  return clean;
}

/**
 * Drives one provider CLI through a Windows ConPTY and resolves with the raw
 * accumulated screen — the same bytes the Python wrappers print to stdout, so
 * the existing parseAgyOutput/parseCodexOutput/parseCursorOutput consume it
 * unchanged.
 *
 * Never rejects: a failure to even load node-pty resolves as an empty capture,
 * which the parsers already classify as "could not find quota panel".
 */
function driveWindows({
  providerId,
  binaryPath,
  env,
  trackChild,
  log = () => {},
  // Injected by the tests so the state machine can be driven against a fake
  // terminal. Production never passes it — node-pty is loaded lazily below,
  // because on a machine where it failed to build, requiring it at module
  // scope would take the whole app down instead of one provider.
  ptyModule = null,
}) {
  const spec = SPECS[providerId];
  if (!spec) return Promise.resolve("");

  let nodePty = ptyModule;
  if (!nodePty) {
    try {
      nodePty = require("node-pty");
    } catch (e) {
      log(`${providerId}: node-pty load failed:`, e.message);
      return Promise.resolve("");
    }
  }

  return new Promise((resolve) => {
    let proc;
    try {
      proc = trackChild(
        nodePty.spawn(resolveLaunchable(binaryPath), spec.args, {
          name: "xterm",
          // 200x60 matches the TIOCSWINSZ the wrappers set — the default 30
          // rows truncates the bottom of the quota panels.
          cols: 200,
          rows: 60,
          cwd: os.homedir(),
          env: { ...env, TERM: "xterm", FORCE_COLOR: "0" },
        })
      );
    } catch (e) {
      log(`${providerId}: ConPTY spawn failed:`, e.message);
      return resolve("");
    }

    let buf = "";
    let settled = false;
    const start = Date.now();
    let lastData = start;
    let lastEnter = 0;
    let readySeenAt = null;
    let typedCommand = false;
    let commandSentAt = null;
    let enterAfterCommandAt = null;

    const finish = () => {
      if (settled) return;
      settled = true;
      clearInterval(ticker);
      try {
        proc.kill();
      } catch (e) {
        /* already gone */
      }
      log(`${providerId}: captured ${buf.length} bytes`);
      resolve(buf);
    };

    const write = (s) => {
      try {
        proc.write(s);
        return true;
      } catch (e) {
        return false;
      }
    };

    proc.onData((data) => {
      if (settled) return;
      buf += data;
      lastData = Date.now();
    });
    proc.onExit(finish);

    // The wrappers poll their PTY on a 100ms select() and re-evaluate the
    // whole state machine each pass; an interval is the same shape here, with
    // onData above standing in for the read.
    const ticker = setInterval(() => {
      if (settled) return;
      const now = Date.now();
      if (now - start > spec.totalTimeoutMs) return finish();

      const idleFor = now - lastData;

      if (readySeenAt === null && buf.includes(spec.readyMarker)) readySeenAt = now;

      // Nudge through first-run onboarding, which blocks the ready prompt.
      // Capped so a stuck or offline sign-in can't spin for the full timeout.
      if (
        readySeenAt === null &&
        spec.wizardNudgeMs > 0 &&
        idleFor > spec.idleQuietMs &&
        now - lastEnter > spec.wizardNudgeIntervalMs &&
        now - start < spec.wizardNudgeMs
      ) {
        if (write("\r")) lastEnter = now;
      }

      if (readySeenAt !== null && !typedCommand && idleFor > spec.idleQuietMs && now - readySeenAt > 300) {
        if (write(spec.typedCommand)) {
          typedCommand = true;
          commandSentAt = now;
          // The wrappers reset their idle clock here too: our own keystrokes
          // are activity, and treating the moment before the CLI echoes them
          // as "idle" would fire the Enter below immediately.
          lastData = now;
        }
      }

      if (typedCommand && enterAfterCommandAt === null && now - commandSentAt > 1000) {
        if (write("\r")) enterAfterCommandAt = now;
      }

      // Quiet alone isn't enough: a cold session has a real network round trip
      // between the command running and the panel painting, and 1s of silence
      // lands right in that gap. Wait for the panel marker, falling back to
      // idle-only after panelFallbackMs so a changed marker — or a genuinely
      // logged-out session that never renders one — can't hang the capture.
      if (enterAfterCommandAt !== null && idleFor > spec.idleQuietMs) {
        if (buf.includes(spec.panelMarker) || now - enterAfterCommandAt > spec.panelFallbackMs) {
          return finish();
        }
      }
    }, 100);
  });
}

module.exports = { SPECS, driveWindows, resolveLaunchable };
